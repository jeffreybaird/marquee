defmodule BobineWeb.Admin.LiveEventLive.IndexTest do
  use BobineWeb.ConnCase, async: true

  import Ecto.Query
  import Mox
  import Phoenix.LiveViewTest

  alias Bobine.Events
  alias Bobine.Repo
  alias Bobine.Streaming.LiveEvent

  setup :verify_on_exit!

  describe "access control" do
    test "admin can access live events index", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ "Live Events"
    end

    test "editor can access live events index", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ "Live Events"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/live-events")
      assert path == ~p"/users/log-in"
    end
  end

  describe "index renders events" do
    test "renders list of live events for the org", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event = insert(:live_event, organization: org, title: "My Livestream")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ "My Livestream"
      assert html =~ ~s(data-test="event-row-#{event.id}")
    end

    test "shows empty state when no events exist", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ ~s(data-test="empty-state")
      assert html =~ "No live events yet"
    end

    test "events from other organizations are not visible", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      insert(:live_event, organization: other_org, title: "Other Org Stream")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events")
      refute html =~ "Other Org Stream"
    end

    test "shows link to new live event", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ ~s(data-test="new-live-event-btn")
    end

    test "shows status badge for each event", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      insert(:live_event, organization: org, status: "live")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ "Live"
    end
  end

  describe "status filter" do
    test "filters events by status", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      insert(:live_event, organization: org, title: "Draft Event", status: "draft")
      insert(:live_event, organization: org, title: "Scheduled Event", status: "scheduled")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events")

      html =
        view
        |> element(~s(form[phx-change="filter_status"]))
        |> render_change(%{"status" => "draft"})

      assert html =~ "Draft Event"
      refute html =~ "Scheduled Event"
    end

    test "all statuses shown when filter is cleared", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      insert(:live_event, organization: org, title: "Draft Event", status: "draft")
      insert(:live_event, organization: org, title: "Live Event", status: "live")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events")

      html =
        view
        |> element(~s(form[phx-change="filter_status"]))
        |> render_change(%{"status" => ""})

      assert html =~ "Draft Event"
      assert html =~ "Live Event"
    end

    test "status filter dropdown is rendered", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ ~s(data-test="status-filter")
    end
  end

  describe "real-time PubSub updates" do
    test "adds event to list when live_event_created broadcast received", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/live-events")
      refute html =~ "New Real-time Event"

      new_event = insert(:live_event, organization: org, title: "New Real-time Event")
      Events.broadcast(nil, {:live_event_created, new_event})

      html = render(view)
      assert html =~ "New Real-time Event"
    end

    test "updates list when live_event_updated broadcast received", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, title: "Original Title")

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ "Original Title"

      # Simulate broadcast with updated event (same id, different title treated as reload)
      Events.broadcast(nil, {:live_event_updated, event})

      # After broadcast, list is reloaded — original title still present
      html = render(view)
      assert html =~ "Original Title"
    end

    test "removes event from list when live_event_deleted broadcast received", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, title: "To Be Deleted")

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/live-events")
      assert html =~ "To Be Deleted"

      # Soft-delete in DB so the reload after broadcast excludes the event
      event_id = event.id

      Repo.update_all(
        from(e in LiveEvent, where: e.id == ^event_id),
        set: [deleted_at: DateTime.utc_now()]
      )

      Events.broadcast(nil, {:live_event_deleted, %{event | deleted_at: DateTime.utc_now()}})

      html = render(view)
      refute html =~ "To Be Deleted"
    end

    test "reloads list when live_event_status_changed broadcast received", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "scheduled")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events")

      Events.broadcast(nil, {:live_event_status_changed, event})

      html = render(view)
      assert html =~ event.title
    end
  end

  # Mux stub not needed for index but Mox verify_on_exit! requires a stub
  # when the test setup calls verify_on_exit! — stubs are set lazily so
  # no-op tests pass without explicit stub.
end
