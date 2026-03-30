defmodule BobineWeb.Admin.MembershipAccessTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "membership-based access control" do
    test "authenticated user with no membership cannot access /admin", %{conn: conn} do
      org = insert(:organization)
      user = insert(:user)
      # User exists but has NO membership in this org
      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> log_in_user(user)

      # Should be denied — either redirect or error, not rendered
      result = live(conn, ~p"/admin")

      case result do
        {:error, {:redirect, _}} -> assert true
        {:ok, _view, html} -> refute html =~ ~s(data-test="org-name")
      end
    end

    test "user from org A cannot access org B's admin", %{conn: conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      user = insert(:user)
      # User is member of org_a only
      insert(:membership, organization: org_a, user: user, role: :admin)

      conn =
        conn
        |> Map.put(:host, "#{org_b.slug}.localhost")
        |> log_in_user(user)

      result = live(conn, ~p"/admin")

      case result do
        {:error, {:redirect, _}} -> assert true
        {:ok, _view, html} -> refute html =~ org_b.name
      end
    end
  end
end
