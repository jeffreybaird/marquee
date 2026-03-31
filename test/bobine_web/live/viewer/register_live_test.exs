defmodule BobineWeb.Viewer.RegisterLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /register" do
    test "renders registration form with org name", %{conn: _conn} do
      org = insert(:organization, name: "Acme Studio")

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, _view, html} = live(conn, ~p"/register")
      assert html =~ "Create your account"
      assert html =~ "Acme Studio"
      assert html =~ ~s(data-test="register-form")
    end

    test "valid registration shows check your email message", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/register")

      html =
        view
        |> form("#register-form", viewer: %{email: "new@example.com", display_name: "New Viewer"})
        |> render_submit()

      assert html =~ "Check your email for a sign-in link."
      assert has_element?(view, "[data-test='check-email-message']")
    end

    test "duplicate email shows same confirmation message (anti-enumeration)", %{conn: _conn} do
      org = insert(:organization)
      _existing = insert(:viewer, organization: org, email: "taken@example.com")

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/register")

      html =
        view
        |> form("#register-form", viewer: %{email: "taken@example.com"})
        |> render_submit()

      assert html =~ "Check your email for a sign-in link."
      assert has_element?(view, "[data-test='check-email-message']")
    end

    test "missing email shows validation error", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/register")

      html =
        view
        |> form("#register-form", viewer: %{email: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
      refute has_element?(view, "[data-test='check-email-message']")
    end

    test "invalid email format shows validation error", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/register")

      _html =
        view
        |> form("#register-form", viewer: %{email: "notavalidemail"})
        |> render_submit()

      # Should show a validation error, NOT the check-email message
      refute has_element?(view, "[data-test='check-email-message']")
    end

    test "cross-org isolation: same email on different org succeeds", %{conn: _conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      _existing = insert(:viewer, organization: org_a, email: "cross@example.com")

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org_b.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/register")

      html =
        view
        |> form("#register-form", viewer: %{email: "cross@example.com", display_name: "Cross"})
        |> render_submit()

      assert html =~ "Check your email for a sign-in link."
    end
  end
end
