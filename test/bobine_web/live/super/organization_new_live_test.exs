defmodule BobineWeb.Super.OrganizationNewLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bobine.Accounts
  alias Bobine.Branding

  describe "GET /super/organizations/new" do
    test "super admin can access new org form", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, _view, html} = live(conn, ~p"/super/organizations/new")
      assert html =~ "New Organization"
    end

    test "creates org with valid data and redirects to show page", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      owner = insert(:user)

      {:ok, view, _html} = live(conn, ~p"/super/organizations/new")

      assert {:ok, conn} =
               view
               |> form("form", %{
                 "org" => %{"name" => "Test Org", "slug" => "test-org", "custom_domain" => ""},
                 "owner_email" => owner.email
               })
               |> render_submit()
               |> follow_redirect(conn)

      assert conn.resp_body =~ "Test Org"
    end

    test "creates default theme for the new org", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      owner = insert(:user)

      {:ok, view, _html} = live(conn, ~p"/super/organizations/new")

      {:ok, _conn} =
        view
        |> form("form", %{
          "org" => %{"name" => "Themed Org", "slug" => "themed-org", "custom_domain" => ""},
          "owner_email" => owner.email
        })
        |> render_submit()
        |> follow_redirect(conn)

      {:ok, org} = Accounts.get_organization_by_slug("themed-org")
      assert Branding.get_theme_by_org(org) != nil
    end

    test "creates owner membership for the specified email", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      owner = insert(:user)

      {:ok, view, _html} = live(conn, ~p"/super/organizations/new")

      {:ok, _conn} =
        view
        |> form("form", %{
          "org" => %{
            "name" => "Membership Org",
            "slug" => "membership-org",
            "custom_domain" => ""
          },
          "owner_email" => owner.email
        })
        |> render_submit()
        |> follow_redirect(conn)

      {:ok, org} = Accounts.get_organization_by_slug("membership-org")
      membership = Accounts.get_membership(org, owner)
      assert membership.role == :owner
    end

    test "creates a new user if email doesn't exist", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      new_email = "brand-new-user-#{System.unique_integer()}@example.com"

      {:ok, view, _html} = live(conn, ~p"/super/organizations/new")

      {:ok, _conn} =
        view
        |> form("form", %{
          "org" => %{
            "name" => "New User Org",
            "slug" => "new-user-org-#{System.unique_integer()}",
            "custom_domain" => ""
          },
          "owner_email" => new_email
        })
        |> render_submit()
        |> follow_redirect(conn)

      assert Accounts.get_user_by_email(new_email) != nil
    end

    test "shows validation errors for missing name", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)

      {:ok, view, _html} = live(conn, ~p"/super/organizations/new")

      html =
        view
        |> form("form", %{
          "org" => %{"name" => "", "slug" => "some-slug", "custom_domain" => ""},
          "owner_email" => "owner@example.com"
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "shows error for duplicate slug", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      insert(:organization, slug: "taken-slug")
      owner = insert(:user)

      {:ok, view, _html} = live(conn, ~p"/super/organizations/new")

      html =
        view
        |> form("form", %{
          "org" => %{"name" => "Duplicate", "slug" => "taken-slug", "custom_domain" => ""},
          "owner_email" => owner.email
        })
        |> render_submit()

      assert html =~ "has already been taken"
    end
  end
end
