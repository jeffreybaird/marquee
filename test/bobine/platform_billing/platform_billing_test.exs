defmodule Bobine.PlatformBillingTest do
  use Bobine.DataCase, async: true

  import Mox

  alias Bobine.PlatformBilling
  setup :verify_on_exit!

  ## -----------------------------------------------------------------------
  ## Plan management
  ## -----------------------------------------------------------------------

  describe "list_platform_plans/1" do
    test "returns all active plans" do
      _plan1 = insert(:platform_plan, slug: "p1", usage_tier: :basic, business_tier: :individual)

      _plan2 =
        insert(:platform_plan, slug: "p2", usage_tier: :super, business_tier: :small_business)

      _inactive =
        insert(:platform_plan,
          slug: "p3",
          usage_tier: :premium,
          business_tier: :enterprise,
          active: false
        )

      result = PlatformBilling.list_platform_plans()
      slugs = Enum.map(result.results, & &1.slug)
      assert "p1" in slugs
      assert "p2" in slugs
      refute "p3" in slugs
    end

    test "returns inactive plans when include_inactive is true" do
      _active = insert(:platform_plan, slug: "a1", usage_tier: :basic, business_tier: :individual)

      _inactive =
        insert(:platform_plan,
          slug: "a2",
          usage_tier: :super,
          business_tier: :small_business,
          active: false
        )

      result = PlatformBilling.list_platform_plans(include_inactive: true)
      slugs = Enum.map(result.results, & &1.slug)
      assert "a1" in slugs
      assert "a2" in slugs
    end
  end

  describe "get_platform_plan/1" do
    test "returns plan when found" do
      plan = insert(:platform_plan)
      assert {:ok, found} = PlatformBilling.get_platform_plan(plan.id)
      assert found.id == plan.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} =
               PlatformBilling.get_platform_plan(Ecto.UUID.generate())
    end
  end

  describe "get_platform_plan_by_slug/1" do
    test "returns correct plan" do
      plan =
        insert(:platform_plan,
          slug: "test_slug",
          usage_tier: :premium,
          business_tier: :enterprise
        )

      assert {:ok, found} = PlatformBilling.get_platform_plan_by_slug("test_slug")
      assert found.id == plan.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} =
               PlatformBilling.get_platform_plan_by_slug("nonexistent")
    end
  end

  describe "create_platform_plan/1" do
    test "creates plan with valid attrs and syncs to Stripe" do
      attrs = %{
        name: "Test Plan",
        slug: "test_plan",
        amount: 4900,
        usage_tier: :basic,
        business_tier: :individual
      }

      expect(Bobine.Billing.MockStripeClient, :create_product, fn params ->
        assert params.name == "Test Plan"
        assert params.metadata.platform_plan_id
        {:ok, %{id: "prod_test_123"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :create_price, fn params ->
        assert params.product == "prod_test_123"
        assert params.unit_amount == 4900
        assert params.currency == "usd"
        assert params.recurring == %{interval: "month"}
        {:ok, %{id: "price_test_123"}}
      end)

      assert {:ok, plan} = PlatformBilling.create_platform_plan(attrs)
      assert plan.name == "Test Plan"
      assert plan.slug == "test_plan"
      assert plan.amount == 4900
      assert plan.usage_tier == :basic
      assert plan.business_tier == :individual
      assert plan.stripe_product_id == "prod_test_123"
      assert plan.stripe_price_id == "price_test_123"
    end

    test "returns error for missing required fields" do
      assert {:error, :validation, changeset} = PlatformBilling.create_platform_plan(%{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:slug]
      assert errors[:amount]
      assert errors[:usage_tier]
      assert errors[:business_tier]
    end
  end

  describe "update_platform_plan/2" do
    test "syncs to Stripe when stripe_price_id is nil" do
      plan = insert(:platform_plan, stripe_price_id: nil, stripe_product_id: nil)

      expect(Bobine.Billing.MockStripeClient, :create_product, fn params ->
        assert params.name == "Updated"
        {:ok, %{id: "prod_synced_123"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :create_price, fn params ->
        assert params.product == "prod_synced_123"
        {:ok, %{id: "price_synced_123"}}
      end)

      assert {:ok, updated} = PlatformBilling.update_platform_plan(plan, %{name: "Updated"})
      assert updated.name == "Updated"
      assert updated.stripe_product_id == "prod_synced_123"
      assert updated.stripe_price_id == "price_synced_123"
    end

    test "updates Stripe product details without replacing the price when only catalog fields change" do
      plan =
        insert(:platform_plan,
          stripe_price_id: "price_existing",
          stripe_product_id: "prod_existing",
          name: "Original",
          description: "Original description"
        )

      expect(Bobine.Billing.MockStripeClient, :update_product, fn "prod_existing", params ->
        assert params.name == "Updated"
        assert params.description == "Updated description"
        assert params.metadata.platform_plan_id == plan.id
        {:ok, %{id: "prod_existing"}}
      end)

      assert {:ok, updated} =
               PlatformBilling.update_platform_plan(plan, %{
                 name: "Updated",
                 description: "Updated description"
               })

      assert updated.name == "Updated"
      assert updated.stripe_price_id == "price_existing"
    end

    test "replaces Stripe price when billing fields change" do
      plan =
        insert(:platform_plan,
          stripe_price_id: "price_existing",
          stripe_product_id: "prod_existing",
          amount: 4900,
          interval: :monthly
        )

      expect(Bobine.Billing.MockStripeClient, :create_price, fn params ->
        assert params.product == "prod_existing"
        assert params.unit_amount == 7900
        assert params.currency == "usd"
        assert params.recurring == %{interval: "month"}
        {:ok, %{id: "price_replacement"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :deactivate_price, fn "price_existing" ->
        {:ok, %{id: "price_existing", active: false}}
      end)

      assert {:ok, updated} = PlatformBilling.update_platform_plan(plan, %{amount: 7900})
      assert updated.amount == 7900
      assert updated.stripe_price_id == "price_replacement"
    end

    test "rolls back local changes when Stripe sync fails" do
      plan =
        insert(:platform_plan,
          stripe_price_id: "price_existing",
          stripe_product_id: "prod_existing",
          name: "Original"
        )

      expect(Bobine.Billing.MockStripeClient, :update_product, fn "prod_existing", _params ->
        {:error, :boom}
      end)

      assert {:error, :stripe_error, :boom} =
               PlatformBilling.update_platform_plan(plan, %{name: "Updated"})

      reloaded = PlatformBilling.get_platform_plan!(plan.id)
      assert reloaded.name == "Original"
    end
  end

  describe "deactivate_platform_plan/1" do
    test "hides plan from selection" do
      plan = insert(:platform_plan, active: true)
      assert {:ok, deactivated} = PlatformBilling.deactivate_platform_plan(plan)
      assert deactivated.active == false
    end
  end

  ## -----------------------------------------------------------------------
  ## Subscription
  ## -----------------------------------------------------------------------

  describe "get_subscription/1" do
    test "returns org's active subscription" do
      org = insert(:organization)
      plan = insert(:platform_plan)
      sub = insert(:platform_subscription, organization: org, platform_plan: plan)

      assert {:ok, found} = PlatformBilling.get_subscription(org)
      assert found.id == sub.id
    end

    test "returns error when no subscription" do
      org = insert(:organization)
      assert {:error, :not_found} = PlatformBilling.get_subscription(org)
    end
  end

  describe "create_org_checkout/3" do
    test "returns Stripe Checkout Session" do
      org = insert(:organization)
      plan = insert(:platform_plan, stripe_price_id: "price_test_123")
      user = insert(:user)

      expect(Bobine.Billing.MockStripeClient, :create_checkout_session, fn params, opts ->
        assert params.mode == "subscription"
        assert List.first(params.line_items).price == "price_test_123"
        assert params.metadata.organization_id == org.id
        assert params.metadata.platform_plan_id == plan.id
        assert Keyword.has_key?(opts, :idempotency_key)
        {:ok, %{"id" => "cs_test_123", "url" => "https://checkout.stripe.com/test"}}
      end)

      assert {:ok, session} = PlatformBilling.create_org_checkout(org, plan, user)
      assert session["url"] =~ "checkout.stripe.com"
    end

    test "uses Bobine's Stripe account, not Connect" do
      org = insert(:organization, stripe_connect_account_id: "acct_connect_123")
      plan = insert(:platform_plan, stripe_price_id: "price_test_456")
      user = insert(:user)

      expect(Bobine.Billing.MockStripeClient, :create_checkout_session, fn params, _opts ->
        # No stripe_account header — this is a direct charge to Bobine's account
        refute Map.has_key?(params, :stripe_account)
        {:ok, %{"id" => "cs_test_456", "url" => "https://checkout.stripe.com/test"}}
      end)

      assert {:ok, _session} = PlatformBilling.create_org_checkout(org, plan, user)
    end
  end

  describe "create_subscription_from_checkout/3" do
    test "creates PlatformSubscription" do
      org = insert(:organization)
      plan = insert(:platform_plan)

      session = %{
        "subscription" => "sub_test_123",
        "customer" => "cus_test_123"
      }

      assert {:ok, sub} =
               PlatformBilling.create_subscription_from_checkout(org, plan, session)

      assert sub.organization_id == org.id
      assert sub.platform_plan_id == plan.id
      assert sub.stripe_subscription_id == "sub_test_123"
      assert sub.stripe_customer_id == "cus_test_123"
      assert sub.status == :active
    end
  end

  describe "change_plan/2 via update_subscription_from_stripe" do
    test "updates subscription to new plan" do
      org = insert(:organization)
      old_plan = insert(:platform_plan, slug: "old", stripe_price_id: "price_old")

      new_plan =
        insert(:platform_plan,
          slug: "new",
          stripe_price_id: "price_new",
          usage_tier: :super,
          business_tier: :small_business
        )

      sub =
        insert(:platform_subscription,
          organization: org,
          platform_plan: old_plan,
          stripe_subscription_id: "sub_change"
        )

      stripe_data = %{
        "id" => "sub_change",
        "status" => "active",
        "current_period_start" => DateTime.to_unix(DateTime.utc_now()),
        "current_period_end" => DateTime.to_unix(DateTime.utc_now() |> DateTime.add(30, :day)),
        "cancel_at_period_end" => false,
        "canceled_at" => nil,
        "items" => %{
          "data" => [%{"price" => %{"id" => "price_new"}}]
        }
      }

      assert {:ok, updated} =
               PlatformBilling.update_subscription_from_stripe(sub, stripe_data)

      assert updated.platform_plan_id == new_plan.id
    end
  end

  describe "cancel_subscription_from_stripe/1" do
    test "marks as canceled" do
      sub = insert(:platform_subscription, status: :active)

      assert {:ok, canceled} = PlatformBilling.cancel_subscription_from_stripe(sub)
      assert canceled.status == :canceled
      assert canceled.canceled_at
    end
  end

  ## -----------------------------------------------------------------------
  ## Feature syncing
  ## -----------------------------------------------------------------------

  describe "sync_features_to_plan/2" do
    test "sets org's feature flags from plan's enabled_features" do
      org = insert(:organization, features: %{})

      plan =
        insert(:platform_plan,
          enabled_features: ["custom_domain", "advanced_drm", "api_access"]
        )

      assert {:ok, updated_org} = PlatformBilling.sync_features_to_plan(org, plan)
      assert updated_org.features["custom_domain"] == true
      assert updated_org.features["advanced_drm"] == true
      assert updated_org.features["api_access"] == true
    end

    test "upgrading plan adds new feature flags" do
      org = insert(:organization, features: %{"custom_domain" => true})

      enterprise_plan =
        insert(:platform_plan,
          slug: "ent",
          usage_tier: :premium,
          business_tier: :enterprise,
          enabled_features: [
            "custom_domain",
            "advanced_drm",
            "live_streaming",
            "ai_recommendations"
          ]
        )

      assert {:ok, updated_org} =
               PlatformBilling.sync_features_to_plan(org, enterprise_plan)

      assert updated_org.features["custom_domain"] == true
      assert updated_org.features["live_streaming"] == true
      assert updated_org.features["ai_recommendations"] == true
    end

    test "downgrading plan removes feature flags" do
      org =
        insert(:organization,
          features: %{"custom_domain" => true, "live_streaming" => true, "api_access" => true}
        )

      basic_plan =
        insert(:platform_plan,
          slug: "basic_down",
          usage_tier: :basic,
          business_tier: :individual,
          enabled_features: []
        )

      assert {:ok, updated_org} = PlatformBilling.sync_features_to_plan(org, basic_plan)
      assert updated_org.features == %{}
    end

    test "canceling subscription clears feature flags to default" do
      org =
        insert(:organization,
          features: %{"custom_domain" => true, "live_streaming" => true}
        )

      assert {:ok, updated_org} =
               PlatformBilling.sync_features_to_plan(org, PlatformBilling.default_free_plan())

      assert updated_org.features == %{}
    end
  end
end
