defmodule MarqueeWeb.Viewer.SubscribeLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /subscribe" do
    test "unauthenticated user redirected to /login", %{conn: _conn} do
      org = insert(:organization)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/subscribe")
    end

    test "renders subscribe page for authenticated viewer", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/subscribe")
      assert html =~ "Choose a plan"
      assert html =~ org.name
    end

    test "displays plans for the org", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      _plan = insert(:plan, organization: org, name: "Monthly Premium", amount: 999)

      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/subscribe")
      assert html =~ "Monthly Premium"
      assert has_element?(view, "[data-test='subscribe-plan-list']")
    end

    test "does not display plans from other orgs (tenant isolation)", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")
      _own_plan = insert(:plan, organization: org, name: "Own Plan")
      _other_plan = insert(:plan, organization: other_org, name: "Other Org Plan")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/subscribe")
      assert html =~ "Own Plan"
      refute html =~ "Other Org Plan"
    end

    test "shows no plans message when org has no plans", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/subscribe")
      assert html =~ "No plans available yet"
    end

    test "dev mode activation button present in dev mode", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      {:ok, view, _html} = live(conn_for_viewer(viewer), ~p"/subscribe")

      if Application.get_env(:marquee, :dev_routes, false) do
        assert has_element?(view, "[data-test='subscribe-dev-activate-btn']")
      end
    end
  end
end
