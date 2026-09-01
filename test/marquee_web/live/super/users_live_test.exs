defmodule MarqueeWeb.Super.UsersLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /super/users" do
    test "lists all users", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      user = insert(:user)

      {:ok, _view, html} = live(conn, ~p"/super/users")
      assert html =~ user.email
    end

    test "shows super admin badge for super admins", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/users")
      assert html =~ ~s(data-test="super-admin-badge-#{super_admin.id}")
    end

    test "grant super admin action works", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      regular_user = insert(:user, is_super_admin: false)

      {:ok, view, _html} = live(conn, ~p"/super/users")

      html =
        view
        |> element("[data-test='grant-super-admin-#{regular_user.id}']")
        |> render_click()

      assert html =~ ~s(data-test="super-admin-badge-#{regular_user.id}")
    end

    test "revoke super admin shows confirmation first", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      other_admin = insert(:super_admin)

      {:ok, view, _html} = live(conn, ~p"/super/users")

      html =
        view
        |> element("[data-test='revoke-super-admin-#{other_admin.id}']")
        |> render_click()

      assert html =~ ~s(data-test="confirm-revoke-#{other_admin.id}")
    end

    test "revoke super admin action works after confirmation", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      other_admin = insert(:super_admin)

      {:ok, view, _html} = live(conn, ~p"/super/users")

      view
      |> element("[data-test='revoke-super-admin-#{other_admin.id}']")
      |> render_click()

      html =
        view
        |> element("[data-test='confirm-revoke-#{other_admin.id}']")
        |> render_click()

      refute html =~ ~s(data-test="super-admin-badge-#{other_admin.id}")
    end

    test "cannot revoke your own super admin status", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, view, _html} = live(conn, ~p"/super/users")

      # Trigger confirm step for self
      view
      |> element("[data-test='revoke-super-admin-#{super_admin.id}']")
      |> render_click()

      html =
        view
        |> element("[data-test='confirm-revoke-#{super_admin.id}']")
        |> render_click()

      assert html =~ "cannot revoke your own"
      # Still a super admin
      updated = Marquee.Repo.get!(Marquee.Accounts.User, super_admin.id)
      assert updated.is_super_admin == true
    end
  end
end
