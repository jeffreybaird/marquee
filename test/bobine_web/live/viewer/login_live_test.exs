defmodule BobineWeb.Viewer.LoginLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /login" do
    test "renders login form", %{conn: _conn} do
      org = insert(:organization, name: "Cool Studio")

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, _view, html} = live(conn, ~p"/login")
      assert html =~ "Sign in"
      assert html =~ "Cool Studio"
      assert html =~ ~s(data-test="login-form")
    end

    test "submit shows check your email regardless of email existence", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> form("#login-form", email: "nonexistent@example.com")
        |> render_submit()

      assert html =~ "Check your email for a sign-in link."
      assert has_element?(view, "[data-test='check-email-message']")
    end
  end
end
