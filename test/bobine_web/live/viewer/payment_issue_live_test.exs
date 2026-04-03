defmodule BobineWeb.Viewer.PaymentIssueLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /account/payment-issue" do
    test "renders for past_due viewer", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "past_due")

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/account/payment-issue")
      assert html =~ "Payment issue"
      assert html =~ "Your last payment didn&#39;t go through"
      assert has_element?(view, "[data-test='payment-issue-page']")
      assert has_element?(view, "[data-test='update-payment-btn']")
    end

    test "non-past_due viewer redirected away", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "active")

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/account/payment-issue")
    end
  end
end
