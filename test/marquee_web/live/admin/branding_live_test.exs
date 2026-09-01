defmodule MarqueeWeb.Admin.BrandingLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "legacy /admin/branding redirect" do
    test "admin is redirected to /admin/appearance", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn_for(membership), ~p"/admin/branding")

      assert path == ~p"/admin/appearance"
    end

    test "unauthenticated user is redirected to log-in", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/branding")
      assert path == ~p"/users/log-in"
    end
  end
end
