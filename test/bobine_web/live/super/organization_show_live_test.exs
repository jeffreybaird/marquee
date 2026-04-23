defmodule BobineWeb.Super.OrganizationShowLiveTest do
  use BobineWeb.ConnCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  import Phoenix.LiveViewTest

  describe "GET /super/organizations/:id" do
    test "displays org details", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization, name: "Show Org", custom_domain: "show.example.com")

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")
      assert html =~ "Show Org"
      assert html =~ "show.example.com"
    end

    test "shows member list", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :editor)

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")
      assert html =~ user.email
      assert html =~ "editor"
    end

    test "impersonate button is present", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")
      assert html =~ ~s(data-test="impersonate-btn")
    end

    test "non-super-admin cannot access", %{conn: _conn} do
      user = insert(:user, is_super_admin: false)
      membership = insert(:membership, user: user)
      conn = conn_for(membership)
      org = insert(:organization)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/super/organizations/#{org.id}")
    end
  end

  describe "feature flags section" do
    test "renders all known features", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")

      assert html =~ ~s(data-test="feature-flags-section")

      for feature <- Bobine.Features.known_features() do
        assert html =~ ~s(data-test="feature-flag-#{feature}"),
               "Expected feature flag row for #{feature}"

        assert html =~ ~s(data-test="toggle-feature-#{feature}"),
               "Expected toggle button for #{feature}"
      end
    end

    test "shows disabled features as Disabled", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization, features: %{})

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")

      [feature | _] = Bobine.Features.known_features()
      assert html =~ ~s(aria-pressed="false")
      refute html =~ ~s(data-test="toggle-feature-#{feature}") and html =~ "Enabled"
    end

    test "toggling a disabled feature enables it", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization, features: %{"analytics" => false})

      {:ok, view, _html} = live(conn, ~p"/super/organizations/#{org.id}")

      html =
        view
        |> element(~s([data-test="toggle-feature-analytics"]))
        |> render_click()

      assert html =~ "Feature analytics enabled"
      assert html =~ ~s(aria-pressed="true")
    end

    test "toggling an enabled feature disables it", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization, features: %{"analytics" => true})

      {:ok, view, _html} = live(conn, ~p"/super/organizations/#{org.id}")

      html =
        view
        |> element(~s([data-test="toggle-feature-analytics"]))
        |> render_click()

      assert html =~ "Feature analytics disabled"
      assert html =~ ~s(aria-pressed="false")
    end
  end

  describe "live events section" do
    test "shows no-live-events placeholder when org has none", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")

      assert html =~ ~s(data-test="live-events-section")
      assert html =~ ~s(data-test="no-live-events")
      refute html =~ ~s(data-test="live-events-table")
    end

    test "renders live events for the org", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)

      event =
        insert(:live_event, organization: org, title: "Weekend Premiere", status: "scheduled")

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")

      assert html =~ ~s(data-test="live-events-table")
      assert html =~ ~s(data-test="live-event-row-#{event.id}")
      assert html =~ "Weekend Premiere"
      assert html =~ "scheduled"
    end

    test "shows valid transition buttons for a scheduled event", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "scheduled")

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")

      assert html =~ ~s(data-test="advance-#{event.id}-live")
      assert html =~ ~s(data-test="advance-#{event.id}-canceled")
      assert html =~ ~s(data-test="advance-#{event.id}-did-not-occur")
      refute html =~ ~s(data-test="advance-#{event.id}-scheduled")
      refute html =~ ~s(data-test="advance-#{event.id}-ended")
    end

    test "shows valid transition buttons for a live event", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "live")

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")

      assert html =~ ~s(data-test="advance-#{event.id}-ended")
      refute html =~ ~s(data-test="advance-#{event.id}-live")
      refute html =~ ~s(data-test="advance-#{event.id}-canceled")
    end

    test "shows no transition buttons for ended events", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "ended")

      {:ok, _view, html} = live(conn, ~p"/super/organizations/#{org.id}")

      refute html =~ ~s(data-test="advance-#{event.id}-")
    end

    test "advance event status button transitions the event", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "scheduled")

      {:ok, view, _html} = live(conn, ~p"/super/organizations/#{org.id}")

      html =
        view
        |> element(~s([data-test="advance-#{event.id}-live"]))
        |> render_click()

      assert html =~ "Event advanced to live"
      assert html =~ ~s(data-test="event-status-#{event.id}")
      assert html =~ "live"
    end

    test "invalid transition shows error flash", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)
      event = insert(:live_event, organization: org, status: "ended")

      {:ok, view, _html} = live(conn, ~p"/super/organizations/#{org.id}")

      # Directly send the event bypassing button visibility guard
      html =
        render_click(view, "advance_event_status", %{
          "event-id" => event.id,
          "status" => "live"
        })

      assert html =~ "Invalid transition"
    end

    test "run did-not-occur check inserts and runs the worker", %{conn: _conn} do
      super_admin = insert(:super_admin)
      conn = conn_for_super_admin(super_admin)
      org = insert(:organization)

      # Create a stale scheduled event that the worker would transition
      stale_time =
        DateTime.add(DateTime.utc_now(), -31 * 60, :second) |> DateTime.truncate(:second)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          scheduled_start_at: stale_time
        )

      {:ok, view, _html} = live(conn, ~p"/super/organizations/#{org.id}")

      html =
        view
        |> element(~s([data-test="run-did-not-occur-check"]))
        |> render_click()

      # Flash message confirms the action was triggered
      assert html =~ "Did-not-occur check queued"

      # With inline testing, the worker runs synchronously — verify its side effect
      updated = Bobine.Repo.get!(Bobine.Streaming.LiveEvent, event.id)
      assert updated.status == "did_not_occur"
    end
  end
end
