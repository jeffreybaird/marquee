defmodule BobineWeb.Super.PlansLiveTest do
  use BobineWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  setup :verify_on_exit!

  setup do
    super_admin = insert(:super_admin)
    %{super_admin: super_admin}
  end

  describe "access control" do
    test "only super admins can access", %{conn: conn} do
      regular_user = insert(:user)
      token = Bobine.Accounts.generate_user_session_token(regular_user)

      result =
        conn
        |> init_test_session(%{})
        |> put_session(:user_token, token)
        |> get(~p"/super/plans")

      assert html_response(result, 302)
    end
  end

  describe "plans listing" do
    test "lists all platform plans", %{super_admin: super_admin} do
      insert(:platform_plan,
        slug: "list_plan_1",
        name: "Basic Plan",
        usage_tier: :basic,
        business_tier: :individual
      )

      insert(:platform_plan,
        slug: "list_plan_2",
        name: "Super Plan",
        usage_tier: :super,
        business_tier: :small_business
      )

      {:ok, view, html} =
        super_admin
        |> conn_for_super_admin()
        |> live(~p"/super/plans")

      assert html =~ "Platform Plans"
      assert has_element?(view, "[data-test=plan-row-list_plan_1]")
      assert has_element?(view, "[data-test=plan-row-list_plan_2]")
    end

    test "edit plan updates fields", %{super_admin: super_admin} do
      plan =
        insert(:platform_plan,
          slug: "edit_test",
          name: "Edit Test",
          usage_tier: :premium,
          business_tier: :enterprise,
          amount: 9900,
          stripe_product_id: "prod_existing",
          stripe_price_id: "price_existing"
        )

      expect(Bobine.Billing.MockStripeClient, :update_product, fn "prod_existing", params ->
        assert params.name == "Updated Name"
        {:ok, %{id: "prod_existing"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :create_price, fn params ->
        assert params.product == "prod_existing"
        assert params.unit_amount == 19_900
        {:ok, %{id: "price_replacement"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :deactivate_price, fn "price_existing" ->
        {:ok, %{id: "price_existing", active: false}}
      end)

      {:ok, view, _html} =
        super_admin
        |> conn_for_super_admin()
        |> live(~p"/super/plans")

      # Click edit
      view |> element("[data-test=edit-plan-edit_test]") |> render_click()
      assert has_element?(view, "[data-test=plan-edit-modal]")

      # Submit update
      view
      |> form("#platform-plan-form", %{
        "platform_plan" => %{
          "name" => "Updated Name",
          "slug" => "edit_test",
          "amount" => "19900",
          "usage_tier" => "premium",
          "business_tier" => "enterprise"
        }
      })
      |> render_submit()

      updated = Bobine.PlatformBilling.get_platform_plan!(plan.id)
      assert updated.name == "Updated Name"
      assert updated.amount == 19_900
      assert updated.stripe_price_id == "price_replacement"
      refute has_element?(view, "[data-test=plan-edit-modal]")
    end

    test "Stripe sync failure keeps the modal open and shows an error", %{
      super_admin: super_admin
    } do
      plan =
        insert(:platform_plan,
          slug: "stripe_fail",
          name: "Stripe Fail",
          usage_tier: :premium,
          business_tier: :enterprise,
          amount: 9900,
          stripe_product_id: "prod_existing",
          stripe_price_id: "price_existing"
        )

      expect(Bobine.Billing.MockStripeClient, :update_product, fn "prod_existing", _params ->
        {:error, :boom}
      end)

      {:ok, view, _html} =
        super_admin
        |> conn_for_super_admin()
        |> live(~p"/super/plans")

      view |> element("[data-test=edit-plan-stripe_fail]") |> render_click()

      html =
        view
        |> form("#platform-plan-form", %{
          "platform_plan" => %{
            "name" => "Updated Name",
            "slug" => "stripe_fail",
            "amount" => "9900",
            "usage_tier" => "premium",
            "business_tier" => "enterprise"
          }
        })
        |> render_submit()

      reloaded = Bobine.PlatformBilling.get_platform_plan!(plan.id)
      assert reloaded.name == "Stripe Fail"
      assert has_element?(view, "[data-test=plan-edit-modal]")
      assert html =~ "Could not sync the plan to Stripe."
    end

    test "deactivate plan", %{super_admin: super_admin} do
      plan =
        insert(:platform_plan,
          slug: "deact_test",
          name: "Deactivate Test",
          usage_tier: :basic,
          business_tier: :small_business,
          active: true
        )

      {:ok, view, _html} =
        super_admin
        |> conn_for_super_admin()
        |> live(~p"/super/plans")

      view |> element("[data-test=deactivate-plan-deact_test]") |> render_click()

      updated = Bobine.PlatformBilling.get_platform_plan!(plan.id)
      assert updated.active == false
    end
  end
end
