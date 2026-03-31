defmodule BobineWeb.Viewer.AccountLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /account" do
    test "shows display name and subscription status", %{conn: _conn} do
      org = insert(:organization)

      viewer =
        insert(:subscribed_viewer,
          organization: org,
          display_name: "Jane Doe",
          subscription_status: "active"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/account")
      assert html =~ "Jane Doe"
      assert html =~ "active"
      assert html =~ ~s(data-test="account-display-name")
      assert html =~ ~s(data-test="account-subscription-status")
    end

    test "delete account redirects to home", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")

      html = render_click(view, "delete_account")

      assert_redirect(view, ~p"/")
    end
  end
end
