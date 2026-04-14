defmodule BobineWeb.Components.ViewerLayoutTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "theme CSS variables" do
    test "default theme applies when org has no custom theme", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "--sv-bg-primary: #0F0F0F"
      assert html =~ "--sv-accent: var(--color-accent, #E50914)"
      assert html =~ ~s(data-test="sv-root")
    end

    test "custom theme colors render in CSS variables", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:theme,
        organization: org,
        background: "#112233",
        brand_primary: "#00FF00",
        text_primary: "#EEEEFF"
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "--sv-bg-primary: #112233"
      assert html =~ "--sv-accent: var(--color-accent, #00FF00)"
      assert html =~ "--sv-text-primary: #EEEEFF"
    end

    test "theme from org A does not bleed into org B", %{conn: _conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)
      viewer_a = insert(:viewer, organization: org_a)
      viewer_b = insert(:viewer, organization: org_b)

      insert(:theme, organization: org_a, brand_primary: "#AA0000")
      insert(:theme, organization: org_b, brand_primary: "#BB0000")

      {:ok, _view, html_a} = live(conn_for_viewer(viewer_a), ~p"/")
      {:ok, _view, html_b} = live(conn_for_viewer(viewer_b), ~p"/")

      assert html_a =~ "--sv-accent: var(--color-accent, #AA0000)"
      refute html_a =~ "#BB0000"

      assert html_b =~ "--sv-accent: var(--color-accent, #BB0000)"
      refute html_b =~ "#AA0000"
    end
  end

  describe "navigation" do
    test "navigation shows org logo/name, not Bobine", %{conn: _conn} do
      org = insert(:organization, name: "StreamCo")
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "StreamCo"
      refute html =~ ">Bobine<"
    end

    test "navigation shows Sign In when no viewer session", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      {:ok, _view, html} = live(conn_for(membership), ~p"/")
      assert html =~ ~s(data-test="sign-in-link")
    end

    test "navigation shows avatar when viewer is logged in", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="profile-avatar")
      refute html =~ ~s(data-test="sign-in-link")
    end

    test "navigation active state highlights current page", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      # Home should be active
      assert html =~ ~r/nav-home.*active/s || html =~ ~r/active.*nav-home/s
    end

    test "sv-nav data-test attribute present", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="sv-nav")
    end

    # mobile_nav component removed — mobile navigation not yet implemented
  end
end
