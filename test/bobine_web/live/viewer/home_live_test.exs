defmodule BobineWeb.Viewer.HomeLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET / with org resolved" do
    test "renders org name", %{conn: _conn} do
      org = insert(:organization, name: "My Studio")
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "My Studio"
    end

    test "lists ready videos for the org", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      video =
        insert(:video,
          organization: org,
          title: "Featured Video",
          mux_status: "ready",
          mux_playback_id: "pb_123"
        )

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "Featured Video"
      assert html =~ ~p"/watch/#{video.id}"
    end

    test "does not show videos from other orgs", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      insert(:video, organization: other_org, title: "Other Org Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      refute html =~ "Other Org Video"
    end

    test "shows empty state when no videos exist", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ "No videos available"
    end
  end

  describe "GET / super admin redirect" do
    test "super admin with no org resolved is redirected to /super", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = log_in_user(conn, super_admin)

      # Visit / without org resolution (no subdomain, no ?org param)
      assert {:error, {:live_redirect, %{to: "/super"}}} = live(conn, ~p"/")
    end
  end
end
