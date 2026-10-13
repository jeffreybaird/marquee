defmodule MarqueeWeb.Admin.CouponsLiveTest do
  use MarqueeWeb.ConnCase, async: true

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
    %{org: org, conn: conn}
  end

  describe "GET /admin/coupons" do
    test "lists org's coupons", %{} do
      %{org: org, conn: conn} = admin_setup()

      Marquee.Repo.insert!(%Marquee.Billing.Coupon{
        organization_id: org.id,
        code: "TESTCODE",
        name: "Test Coupon",
        percent_off: Decimal.new("25"),
        duration: :once,
        stripe_coupon_id: "coupon_test",
        stripe_promotion_code_id: "promo_test",
        active: true
      })

      {:ok, view, html} = live(conn, ~p"/admin/coupons")
      assert html =~ "TESTCODE"
      assert has_element?(view, "[data-test='coupons-list']")
    end

    test "coupons from other orgs not visible", %{} do
      %{conn: conn} = admin_setup()
      other_org = insert(:organization)

      Marquee.Repo.insert!(%Marquee.Billing.Coupon{
        organization_id: other_org.id,
        code: "OTHERCODE",
        name: "Other",
        percent_off: Decimal.new("10"),
        duration: :once,
        stripe_coupon_id: "coupon_other",
        stripe_promotion_code_id: "promo_other",
        active: true
      })

      {:ok, _view, html} = live(conn, ~p"/admin/coupons")
      refute html =~ "OTHERCODE"
    end

    test "shows empty state when no coupons", %{} do
      %{conn: conn} = admin_setup()

      {:ok, view, _html} = live(conn, ~p"/admin/coupons")
      assert has_element?(view, "[data-test='coupons-empty']")
    end

    test "create coupon with Stripe mock", %{} do
      %{conn: conn} = admin_setup()

      expect(Marquee.Billing.MockStripeClient, :create_connected_coupon, fn _params, _opts ->
        {:ok, %{id: "coupon_new"}}
      end)

      expect(Marquee.Billing.MockStripeClient, :create_connected_promotion_code, fn _params,
                                                                                    _opts ->
        {:ok, %{id: "promo_new"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/coupons")

      view |> element("[data-test='new-coupon-btn']") |> render_click()
      assert has_element?(view, "[data-test='coupon-form']")

      view
      |> form("#coupon-form", %{
        coupon: %{
          code: "NEWCOUPON",
          name: "New Coupon",
          percent_off: "25",
          duration: "once"
        }
      })
      |> render_submit()

      # After creation, the coupon should appear in the list
      html = render(view)
      assert html =~ "NEWCOUPON"
      refute has_element?(view, "[data-test='coupon-form']")
    end
  end

  describe "coupon form state" do
    test "validate keeps the typed coupon fields" do
      %{conn: conn} = admin_setup()
      {:ok, view, _html} = live(conn, ~p"/admin/coupons")

      view |> element("[data-test='new-coupon-btn']") |> render_click()

      view
      |> form("#coupon-form", %{
        coupon: %{code: "SPRING25", name: "Spring sale", percent_off: "25"}
      })
      |> render_change()

      assert has_element?(view, "[data-test='coupon-code-input'][value='SPRING25']")
      assert has_element?(view, "[data-test='coupon-name-input'][value='Spring sale']")
    end

    test "typed code survives switching the discount type" do
      %{conn: conn} = admin_setup()
      {:ok, view, _html} = live(conn, ~p"/admin/coupons")

      view |> element("[data-test='new-coupon-btn']") |> render_click()

      view
      |> form("#coupon-form", %{coupon: %{code: "FLAT10", name: "Flat ten"}})
      |> render_change()

      view |> element("#coupon-form button[phx-value-type='amount']") |> render_click()

      assert has_element?(view, "#coupon_amount_off")
      refute has_element?(view, "#coupon_percent_off")
      assert has_element?(view, "[data-test='coupon-code-input'][value='FLAT10']")
      assert has_element?(view, "[data-test='coupon-name-input'][value='Flat ten']")
    end
  end
end
