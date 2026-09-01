defmodule MarqueeWeb.Viewer.AccountLiveTest do
  use MarqueeWeb.ConnCase, async: true

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
      assert html =~ ~s(data-test="account-email")
    end

    test "shows email address", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, email: "viewer@test.com")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/account")
      assert html =~ "viewer@test.com"
    end

    test "edit button visible when not impersonating", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")
      assert has_element?(view, "[data-test='account-edit-btn']")
    end

    test "delete account redirects to home", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")

      render_click(view, "delete_account")

      assert_redirect(view, ~p"/")
    end
  end

  describe "edit display name" do
    test "clicking edit shows form, saving updates name", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, display_name: "Old Name")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")

      # Click edit
      render_click(view, "edit")
      assert has_element?(view, "[data-test='account-edit-form']")
      assert has_element?(view, "[data-test='account-display-name-input']")
      assert has_element?(view, "[data-test='account-marketing-opt-in']")

      # Submit with new name
      html =
        view
        |> form("#profile-form", viewer: %{display_name: "New Name"})
        |> render_submit()

      assert html =~ "New Name"
      assert html =~ "Profile updated."
    end

    test "cancel edit returns to display mode", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/account")

      render_click(view, "edit")
      assert has_element?(view, "[data-test='account-edit-form']")

      render_click(view, "cancel_edit")
      refute has_element?(view, "[data-test='account-edit-form']")
      assert has_element?(view, "[data-test='account-edit-btn']")
    end
  end

  describe "impersonation" do
    test "impersonation banner shown when impersonating", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, email: "target@example.com")
      membership = insert(:membership, organization: org, role: :admin)

      conn = conn_for_impersonating_viewer(membership, viewer)
      {:ok, view, html} = live(conn, ~p"/account")

      assert html =~ "target@example.com"
      assert has_element?(view, "[data-test='impersonation-banner']")
      assert has_element?(view, "[data-test='stop-impersonation-btn']")
      assert has_element?(view, "[data-test='viewer-header-identity']")
      assert render(view) =~ "You are impersonating"
      assert render(view) =~ "target@example.com"
    end

    test "edit button hidden when impersonating", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      membership = insert(:membership, organization: org, role: :admin)

      conn = conn_for_impersonating_viewer(membership, viewer)
      {:ok, view, _html} = live(conn, ~p"/account")

      refute has_element?(view, "[data-test='account-edit-btn']")
    end

    test "delete button hidden when impersonating", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      membership = insert(:membership, organization: org, role: :admin)

      conn = conn_for_impersonating_viewer(membership, viewer)
      {:ok, view, _html} = live(conn, ~p"/account")

      refute has_element?(view, "[data-test='account-delete-btn']")
    end
  end
end
