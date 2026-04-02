defmodule Bobine.Workers.StripeWebhookProcessorPlatformTest do
  use Bobine.DataCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  alias Bobine.Workers.StripeWebhookProcessor
  alias Bobine.PlatformBilling

  describe "platform checkout.session.completed" do
    test "creates subscription and syncs features" do
      org = insert(:organization, features: %{})

      plan =
        insert(:platform_plan,
          slug: "sb_super",
          usage_tier: :super,
          business_tier: :small_business,
          enabled_features: ["custom_domain", "advanced_drm", "api_access"]
        )

      event =
        build_platform_event("checkout.session.completed", %{
          "subscription" => "sub_platform_test",
          "customer" => "cus_platform_test",
          "metadata" => %{
            "organization_id" => org.id,
            "platform_plan_id" => plan.id
          }
        })

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => event})

      # Subscription created
      assert {:ok, sub} = PlatformBilling.get_subscription(org)
      assert sub.stripe_subscription_id == "sub_platform_test"
      assert sub.status == :active

      # Features synced
      updated_org = Bobine.Admin.get_organization!(org.id)
      assert updated_org.features["custom_domain"] == true
      assert updated_org.features["advanced_drm"] == true
      assert updated_org.features["api_access"] == true
    end
  end

  describe "platform customer.subscription.updated" do
    test "syncs features on plan change" do
      org = insert(:organization, features: %{"custom_domain" => true})

      old_plan =
        insert(:platform_plan,
          slug: "old_plan",
          stripe_price_id: "price_old",
          enabled_features: ["custom_domain"]
        )

      new_plan =
        insert(:platform_plan,
          slug: "new_plan",
          stripe_price_id: "price_new",
          usage_tier: :premium,
          business_tier: :enterprise,
          enabled_features: ["custom_domain", "live_streaming", "ai_recommendations"]
        )

      insert(:platform_subscription,
        organization: org,
        platform_plan: old_plan,
        stripe_subscription_id: "sub_update_test"
      )

      event =
        build_platform_event("customer.subscription.updated", %{
          "id" => "sub_update_test",
          "status" => "active",
          "current_period_start" => DateTime.to_unix(DateTime.utc_now()),
          "current_period_end" => DateTime.to_unix(DateTime.utc_now() |> DateTime.add(30, :day)),
          "cancel_at_period_end" => false,
          "canceled_at" => nil,
          "items" => %{
            "data" => [%{"price" => %{"id" => "price_new"}}]
          }
        })

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => event})

      updated_org = Bobine.Admin.get_organization!(org.id)
      assert updated_org.features["live_streaming"] == true
      assert updated_org.features["ai_recommendations"] == true
    end
  end

  describe "platform customer.subscription.deleted" do
    test "clears features to defaults" do
      org =
        insert(:organization,
          features: %{"custom_domain" => true, "live_streaming" => true}
        )

      plan = insert(:platform_plan, slug: "del_plan")

      insert(:platform_subscription,
        organization: org,
        platform_plan: plan,
        stripe_subscription_id: "sub_delete_test"
      )

      event =
        build_platform_event("customer.subscription.deleted", %{
          "id" => "sub_delete_test"
        })

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => event})

      updated_org = Bobine.Admin.get_organization!(org.id)
      assert updated_org.features == %{}

      # Subscription marked as canceled
      assert {:ok, sub} = PlatformBilling.get_subscription(org)
      assert sub.status == :canceled
    end
  end

  describe "platform invoice.payment_failed" do
    test "marks subscription as past_due" do
      org = insert(:organization)
      plan = insert(:platform_plan, slug: "fail_plan")

      insert(:platform_subscription,
        organization: org,
        platform_plan: plan,
        stripe_subscription_id: "sub_fail_test",
        status: :active
      )

      event =
        build_platform_event("invoice.payment_failed", %{
          "subscription" => "sub_fail_test"
        })

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => event})

      assert {:ok, sub} = PlatformBilling.get_subscription(org)
      assert sub.status == :past_due
    end
  end

  describe "platform invoice.payment_succeeded" do
    test "restores status to active" do
      org = insert(:organization)
      plan = insert(:platform_plan, slug: "success_plan")

      insert(:platform_subscription,
        organization: org,
        platform_plan: plan,
        stripe_subscription_id: "sub_success_test",
        status: :past_due
      )

      event =
        build_platform_event("invoice.payment_succeeded", %{
          "subscription" => "sub_success_test"
        })

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => event})

      assert {:ok, sub} = PlatformBilling.get_subscription(org)
      assert sub.status == :active
    end
  end

  describe "event routing" do
    test "platform events (no connect account) don't trigger viewer billing handlers" do
      # A platform event with no account field should be handled by platform handlers
      event =
        build_platform_event("checkout.session.completed", %{
          "metadata" => %{}
        })

      # Should not crash, just log and return :ok
      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => event})
    end

    test "viewer events (with connect account) don't trigger platform handlers" do
      org = insert(:organization)
      plan = insert(:platform_plan, slug: "route_plan")

      insert(:platform_subscription,
        organization: org,
        platform_plan: plan,
        stripe_subscription_id: "sub_route_test"
      )

      # A connected account event should be routed to the connect handler
      event = %{
        "id" => "evt_connected",
        "type" => "customer.subscription.deleted",
        "account" => "acct_connect_123",
        "data" => %{
          "object" => %{"id" => "sub_route_test"}
        }
      }

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => event})

      # Platform subscription should NOT be canceled (event was for connected account)
      assert {:ok, sub} = PlatformBilling.get_subscription(org)
      assert sub.status == :active
    end
  end

  ## -----------------------------------------------------------------------
  ## Lifecycle test
  ## -----------------------------------------------------------------------

  describe "platform subscription lifecycle" do
    test "org subscribes to small_business_super, upgrades to enterprise_premium, cancels" do
      org = insert(:organization, features: %{})

      sb_super =
        insert(:platform_plan,
          slug: "small_business_super_lc",
          usage_tier: :super,
          business_tier: :small_business,
          stripe_price_id: "price_sb_super",
          enabled_features: ["custom_domain", "advanced_drm", "api_access"]
        )

      ent_premium =
        insert(:platform_plan,
          slug: "enterprise_premium_lc",
          usage_tier: :premium,
          business_tier: :enterprise,
          stripe_price_id: "price_ent_premium",
          enabled_features: [
            "custom_domain",
            "advanced_drm",
            "api_access",
            "live_streaming",
            "ai_recommendations",
            "priority_support",
            "custom_email_domain",
            "white_label"
          ]
        )

      # 1. Subscribe to small_business_super
      checkout_event =
        build_platform_event("checkout.session.completed", %{
          "subscription" => "sub_lifecycle",
          "customer" => "cus_lifecycle",
          "metadata" => %{
            "organization_id" => org.id,
            "platform_plan_id" => sb_super.id
          }
        })

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => checkout_event})

      org = Bobine.Admin.get_organization!(org.id)
      assert org.features["custom_domain"] == true
      assert org.features["advanced_drm"] == true
      assert org.features["live_streaming"] != true

      # 2. Upgrade to enterprise_premium
      update_event =
        build_platform_event("customer.subscription.updated", %{
          "id" => "sub_lifecycle",
          "status" => "active",
          "current_period_start" => DateTime.to_unix(DateTime.utc_now()),
          "current_period_end" => DateTime.to_unix(DateTime.utc_now() |> DateTime.add(30, :day)),
          "cancel_at_period_end" => false,
          "canceled_at" => nil,
          "items" => %{
            "data" => [%{"price" => %{"id" => "price_ent_premium"}}]
          }
        })

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => update_event})

      org = Bobine.Admin.get_organization!(org.id)
      assert org.features["live_streaming"] == true
      assert org.features["ai_recommendations"] == true
      assert org.features["white_label"] == true

      # 3. Cancel
      deleted_event =
        build_platform_event("customer.subscription.deleted", %{
          "id" => "sub_lifecycle"
        })

      assert :ok = perform_job(StripeWebhookProcessor, %{"event" => deleted_event})

      org = Bobine.Admin.get_organization!(org.id)
      assert org.features == %{}
    end
  end

  ## -----------------------------------------------------------------------
  ## Helpers
  ## -----------------------------------------------------------------------

  defp build_platform_event(type, object) do
    %{
      "id" => "evt_#{Ecto.UUID.generate()}",
      "type" => type,
      "data" => %{
        "object" => object
      }
    }
  end
end
