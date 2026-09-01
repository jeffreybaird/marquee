defmodule MarqueeWeb.Viewer.LoginLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Branding

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

    test "renders polished auth shell with default branded background", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, _view, html} = live(conn, ~p"/login")

      assert html =~ ~s(data-test="login-shell")
      assert html =~ ~s(data-test="login-card")
      # No background image set — shell should not carry the has-bg-image modifier
      refute html =~ "has-bg-image"
      refute html =~ "--sv-auth-bg-image"
    end

    test "applies org-supplied login background image when configured", %{conn: _conn} do
      org = insert(:organization)

      {:ok, _theme} =
        Branding.create_theme(%{
          organization_id: org.id,
          login_background_image_url: "https://cdn.example.com/bg.jpg"
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, _view, html} = live(conn, ~p"/login")

      assert html =~ "has-bg-image"
      assert html =~ "--sv-auth-bg-image"
      assert html =~ "https://cdn.example.com/bg.jpg"
    end

    test "rejects unsafe login background URLs (CSS injection guard)", %{conn: _conn} do
      org = insert(:organization)

      {:ok, _theme} =
        Branding.create_theme(%{
          organization_id: org.id,
          login_background_image_url:
            "https://evil.example.com/bg.jpg'); } body { display: none } /*"
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, _view, html} = live(conn, ~p"/login")

      refute html =~ "has-bg-image"
      refute html =~ "display: none"
      refute html =~ "--sv-auth-bg-image"
    end

    test "renders org logo when theme.logo_url is set", %{conn: _conn} do
      org = insert(:organization)

      {:ok, _theme} =
        Branding.create_theme(%{
          organization_id: org.id,
          logo_url: "https://cdn.example.com/logo.png"
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, _view, html} = live(conn, ~p"/login")

      assert html =~ ~s(data-test="login-logo")
      assert html =~ "https://cdn.example.com/logo.png"
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

    test "banned viewer sees same check email message (anti-enumeration)", %{conn: _conn} do
      org = insert(:organization)
      _banned = insert(:viewer, organization: org, email: "banned@example.com", status: :banned)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> form("#login-form", email: "banned@example.com")
        |> render_submit()

      assert html =~ "Check your email for a sign-in link."
      assert has_element?(view, "[data-test='check-email-message']")
    end

    test "suspended viewer sees same check email message (anti-enumeration)", %{conn: _conn} do
      org = insert(:organization)

      _suspended =
        insert(:viewer, organization: org, email: "suspended@example.com", status: :suspended)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> form("#login-form", email: "suspended@example.com")
        |> render_submit()

      assert html =~ "Check your email for a sign-in link."
      assert has_element?(view, "[data-test='check-email-message']")
    end
  end
end
