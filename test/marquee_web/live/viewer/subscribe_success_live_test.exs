defmodule MarqueeWeb.Viewer.SubscribeSuccessLiveTest do
  @moduledoc """
  Covers pathway coverage for `/subscribe/success` per the E2E Rule in
  `.claude/testing.md`:

    * authenticated viewer with active subscription → page renders with org name
    * authenticated viewer without active subscription → page still renders
      (the route lives in `:viewer_authenticated`, not `:viewer_subscribed`,
      so non-subscribed viewers are expected to land here immediately after
      checkout before the webhook flips their status)
    * unauthenticated viewer → redirected to `/login` by `AssignViewerScope`
    * missing / unexpected query params → graceful no-op (current mount
      accepts `_params`)
    * tenant isolation — only the resolved org's name is shown, never
      another org's
  """

  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /subscribe/success" do
    test "renders success page with org name for authenticated active viewer", %{conn: _conn} do
      org = insert(:organization, name: "Acme Streaming")
      viewer = insert(:subscribed_viewer, organization: org)

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/subscribe/success")

      assert html =~ "Welcome!"
      assert html =~ "Acme Streaming"
      assert has_element?(view, "[data-test='subscribe-success']")
      assert has_element?(view, "[data-test='start-watching-link']")
    end

    test "renders success page for authenticated viewer even without active status", %{
      conn: _conn
    } do
      # Viewers land on /subscribe/success immediately after returning from
      # Stripe Checkout; Stripe's webhook may not have flipped their status
      # to "active" yet. The page must still render in that window.
      org = insert(:organization, name: "Nova Films")
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/subscribe/success")

      assert html =~ "Welcome!"
      assert html =~ "Nova Films"
    end

    test "unauthenticated visitor redirected to /login", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/subscribe/success")
    end

    test "ignores unknown query params and still renders", %{conn: _conn} do
      # The live_view mounts with `_params` and does not read `session_id`,
      # so an arbitrary query string must not crash or alter output.
      org = insert(:organization, name: "Query-Param Org")
      viewer = insert(:subscribed_viewer, organization: org)

      {:ok, _view, html} =
        live(conn_for_viewer(viewer), ~p"/subscribe/success?session_id=cs_test_bogus")

      assert html =~ "Welcome!"
      assert html =~ "Query-Param Org"
    end

    test "ignores missing session_id param and still renders", %{conn: _conn} do
      org = insert(:organization, name: "No-Param Org")
      viewer = insert(:subscribed_viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/subscribe/success")

      assert html =~ "Welcome!"
      assert html =~ "No-Param Org"
    end
  end

  describe "multi-tenant isolation" do
    test "viewer on their own org's success page does not see another org's name",
         %{conn: _conn} do
      org_a = insert(:organization, name: "Org Alpha")
      _org_b = insert(:organization, name: "Org Beta")

      viewer = insert(:subscribed_viewer, organization: org_a)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/subscribe/success")

      assert html =~ "Org Alpha"
      refute html =~ "Org Beta"
    end

    test "unauthenticated visitor on org B's subdomain is redirected, never sees content",
         %{conn: _conn} do
      # Even on an org's own host, a logged-out visitor gets bounced — so
      # they can never observe the success page for any tenant without
      # first authenticating.
      org_b = insert(:organization, name: "Org Beta")

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org_b.slug}.localhost")

      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/subscribe/success")
    end
  end
end
