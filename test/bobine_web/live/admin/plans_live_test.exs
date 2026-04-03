defmodule BobineWeb.Admin.PlansLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  defp admin_setup do
    org =
      insert(:organization,
        stripe_connect_account_id: "acct_test",
        stripe_connect_onboarding_complete: true
      )

    user = insert(:user)
    membership = insert(:membership, user: user, organization: org, role: :admin)
    conn = conn_for(membership)
    %{org: org, conn: conn, membership: membership}
  end

  describe "GET /admin/plans" do
    test "lists org's plans", %{} do
      %{org: org, conn: conn} = admin_setup()
      _plan = insert(:plan, organization: org, name: "Monthly Premium")

      {:ok, view, html} = live(conn, ~p"/admin/plans")
      assert html =~ "Monthly Premium"
      assert has_element?(view, "[data-test='plans-list']")
    end

    test "plans from other orgs not visible", %{} do
      %{org: _org, conn: conn} = admin_setup()
      other_org = insert(:organization)
      _other_plan = insert(:plan, organization: other_org, name: "Other Org Plan")

      {:ok, _view, html} = live(conn, ~p"/admin/plans")
      refute html =~ "Other Org Plan"
    end

    test "shows empty state when no plans", %{} do
      %{conn: conn} = admin_setup()

      {:ok, view, _html} = live(conn, ~p"/admin/plans")
      assert has_element?(view, "[data-test='plans-empty']")
    end

    test "create plan with Stripe mock", %{} do
      %{conn: conn} = admin_setup()

      expect(Bobine.Billing.MockStripeClient, :create_connected_product, fn _params, _opts ->
        {:ok, %{id: "prod_mock"}}
      end)

      expect(Bobine.Billing.MockStripeClient, :create_connected_price, fn _params, _opts ->
        {:ok, %{id: "price_mock"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/plans")

      view |> element("[data-test='new-plan-btn']") |> render_click()
      assert has_element?(view, "[data-test='plan-form']")

      view
      |> form("#plan-form", %{
        plan: %{
          name: "Test Plan",
          amount_dollars: "9.99",
          interval: "monthly"
        }
      })
      |> render_submit()

      # After creation, the plan should appear in the list
      html = render(view)
      assert html =~ "Test Plan"
      refute has_element?(view, "[data-test='plan-form']")
    end

    test "deactivate plan", %{} do
      %{org: org, conn: conn} = admin_setup()
      plan = insert(:plan, organization: org, name: "To Deactivate", active: true)

      {:ok, view, _html} = live(conn, ~p"/admin/plans")

      assert has_element?(view, "[data-test='deactivate-plan-#{plan.id}']")
      view |> element("[data-test='deactivate-plan-#{plan.id}']") |> render_click()

      # After deactivation, reactivate button should appear
      assert has_element?(view, "[data-test='reactivate-plan-#{plan.id}']")
    end
  end
end
