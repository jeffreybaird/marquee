defmodule BobineWeb.Admin.LiveEventLive.ShowTest do
  use BobineWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Bobine.Content.MockMuxClient
  alias Bobine.Events

  setup :verify_on_exit!

  describe "access control" do
    test "editor can access show page", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      assert html =~ event.title
    end

    test "redirects to index for unknown slug", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn_for(membership), ~p"/admin/live-events/nonexistent-slug")

      assert path == ~p"/admin/live-events"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      event = insert(:live_event, organization: org)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/admin/live-events/#{event.slug}")

      assert path == ~p"/users/log-in"
    end
  end

  describe "show page content" do
    test "displays event details", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          title: "My Stream",
          description: "A great stream",
          access_type: "subscribers_only"
        )

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      assert html =~ "My Stream"
      assert html =~ "A great stream"
      assert html =~ "Subscribers Only"
    end

    test "shows edit link", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      assert html =~ ~s(data-test="edit-btn")
    end

    test "shows delete button", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      assert html =~ ~s(data-test="delete-btn")
    end

    test "shows recording link when recording_video_id is set", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      video = insert(:video, organization: org)

      event =
        insert(:live_event,
          organization: org,
          recording_video_id: video.id,
          status: "ended"
        )

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      assert html =~ ~s(data-test="recording-link")
    end
  end

  describe "state transition buttons" do
    test "draft event shows Schedule and Cancel buttons", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "draft")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      assert html =~ ~s(data-test="btn-schedule")
      assert html =~ ~s(data-test="btn-cancel")
      refute html =~ ~s(data-test="btn-go-live")
      refute html =~ ~s(data-test="btn-end-stream")
      refute html =~ ~s(data-test="btn-did-not-occur")
    end

    test "scheduled event shows Go Live, Cancel, and Did Not Occur buttons", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "scheduled")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      assert html =~ ~s(data-test="btn-go-live")
      assert html =~ ~s(data-test="btn-cancel")
      assert html =~ ~s(data-test="btn-did-not-occur")
      refute html =~ ~s(data-test="btn-schedule")
      refute html =~ ~s(data-test="btn-end-stream")
    end

    test "live event shows End Stream button only", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "live")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      assert html =~ ~s(data-test="btn-end-stream")
      refute html =~ ~s(data-test="btn-schedule")
      refute html =~ ~s(data-test="btn-go-live")
      refute html =~ ~s(data-test="btn-cancel")
    end

    test "ended event shows no transition buttons", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "ended")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      refute html =~ ~s(data-test="btn-schedule")
      refute html =~ ~s(data-test="btn-go-live")
      refute html =~ ~s(data-test="btn-cancel")
      refute html =~ ~s(data-test="btn-end-stream")
    end

    test "Schedule button transitions draft to scheduled", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "draft")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      html =
        view
        |> element(~s([data-test="btn-schedule"]))
        |> render_click()

      assert html =~ "Scheduled"
      refute html =~ ~s(data-test="btn-schedule")
    end

    test "End Stream button transitions live to ended", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "live")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      html =
        view
        |> element(~s([data-test="btn-end-stream"]))
        |> render_click()

      assert html =~ "Ended"
      refute html =~ ~s(data-test="btn-end-stream")
    end
  end

  describe "streaming credentials" do
    test "shows Get RTMP Credentials button for draft/scheduled/live events", %{conn: _conn} do
      for status <- ["draft", "scheduled", "live"] do
        org = insert(:organization)
        user = insert(:user)
        membership = insert(:membership, organization: org, user: user, role: :editor)
        event = insert(:live_event, organization: org, status: status)

        {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

        assert html =~ ~s(data-test="get-credentials-btn"),
               "expected credentials button for #{status}"
      end
    end

    test "does not show credentials section for ended/canceled events", %{conn: _conn} do
      for status <- ["ended", "canceled", "did_not_occur"] do
        org = insert(:organization)
        user = insert(:user)
        membership = insert(:membership, organization: org, user: user, role: :editor)
        event = insert(:live_event, organization: org, status: status)

        {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

        refute html =~ ~s(data-test="get-credentials-btn"),
               "expected no credentials button for #{status}"
      end
    end

    test "stream key is NOT pre-rendered in the page HTML", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          mux_live_stream_id: "stream_abc"
        )

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      # Credentials modal should not be rendered (no stream key in HTML)
      refute html =~ ~s(data-test="credentials-modal")
      refute html =~ ~s(data-test="stream-key")
    end

    test "clicking Get RTMP Credentials fetches and shows credentials", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          mux_live_stream_id: "stream_abc"
        )

      Mox.stub(MockMuxClient, :get_live_stream, fn "stream_abc" ->
        {:ok, %{"id" => "stream_abc", "stream_key" => "secret-key-xyz"}}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      html =
        view
        |> element(~s([data-test="get-credentials-btn"]))
        |> render_click()

      assert html =~ ~s(data-test="credentials-modal")
      assert html =~ ~s(data-test="stream-key")
      assert html =~ "secret-key-xyz"
    end

    test "credentials modal can be closed", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          mux_live_stream_id: "stream_abc"
        )

      Mox.stub(MockMuxClient, :get_live_stream, fn _id ->
        {:ok, %{"id" => "stream_abc", "stream_key" => "secret-key"}}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      view
      |> element(~s([data-test="get-credentials-btn"]))
      |> render_click()

      html =
        view
        |> element(~s([data-test="close-credentials-btn"]))
        |> render_click()

      refute html =~ ~s(data-test="credentials-modal")
      refute html =~ "secret-key"
    end

    test "regenerate stream key fetches new credentials", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          mux_live_stream_id: "stream_abc"
        )

      Mox.stub(MockMuxClient, :get_live_stream, fn _id ->
        {:ok, %{"id" => "stream_abc", "stream_key" => "new-key-after-regen"}}
      end)

      Mox.stub(MockMuxClient, :reset_stream_key, fn _id ->
        {:ok, %{"id" => "stream_abc", "stream_key" => "new-key-after-regen"}}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      # Open credentials modal first
      view
      |> element(~s([data-test="get-credentials-btn"]))
      |> render_click()

      # Regenerate key
      html =
        view
        |> element(~s([data-test="regenerate-key-btn"]))
        |> render_click()

      assert html =~ "new-key-after-regen"
    end
  end

  describe "delete" do
    test "shows delete confirmation modal", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org)

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      refute html =~ ~s(data-test="delete-confirm-modal")

      html =
        view
        |> element(~s([data-test="delete-btn"]))
        |> render_click()

      assert html =~ ~s(data-test="delete-confirm-modal")
    end

    test "confirms delete and redirects to index", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      event =
        insert(:live_event,
          organization: org,
          mux_live_stream_id: "stream_abc"
        )

      Mox.stub(MockMuxClient, :delete_live_stream, fn _id -> :ok end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      view
      |> element(~s([data-test="delete-btn"]))
      |> render_click()

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element(~s([data-test="confirm-delete-btn"]))
               |> render_click()

      assert path == ~p"/admin/live-events"
    end

    test "cancel_delete hides confirmation modal", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      view
      |> element(~s([data-test="delete-btn"]))
      |> render_click()

      html =
        view
        |> element(~s([data-test="cancel-delete-btn"]))
        |> render_click()

      refute html =~ ~s(data-test="delete-confirm-modal")
    end
  end

  describe "chat moderation panel" do
    test "moderation panel renders for live event", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "live")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      assert html =~ ~s(data-test="chat-moderation")
      assert html =~ ~s(data-test="mod-message-list")
    end

    test "moderation panel does not render for non-live events", %{conn: _conn} do
      for status <- ["scheduled", "draft", "ended", "canceled"] do
        org = insert(:organization)
        user = insert(:user)
        membership = insert(:membership, organization: org, user: user, role: :editor)
        event = insert(:live_event, organization: org, status: status)

        {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

        refute html =~ ~s(data-test="chat-moderation"),
               "expected no moderation panel for #{status}"
      end
    end

    test "no-messages placeholder shown when no chat messages", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "live")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      assert html =~ ~s(data-test="mod-no-messages")
    end

    test "existing chat messages appear in moderation list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      event = insert(:live_event, organization: org, status: "live")

      {:ok, msg} = Bobine.Streaming.post_chat_message(event, viewer, "hello mods!")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      assert html =~ ~s(data-test="mod-message-#{msg.id}")
      assert html =~ "hello mods!"
    end

    test "delete chat message button removes message from list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      event = insert(:live_event, organization: org, status: "live")

      {:ok, msg} = Bobine.Streaming.post_chat_message(event, viewer, "delete me")

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      assert html =~ ~s(data-test="mod-message-#{msg.id}")

      html =
        view
        |> element(~s([data-test="delete-chat-msg-#{msg.id}"]))
        |> render_click()

      refute html =~ ~s(data-test="mod-message-#{msg.id}")
      assert html =~ "Message deleted"
    end

    test "ban viewer button shows success flash", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      event = insert(:live_event, organization: org, status: "live")

      {:ok, _msg} = Bobine.Streaming.post_chat_message(event, viewer, "ban me!")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")

      html =
        view
        |> element(~s([data-test="ban-viewer-#{viewer.id}"]))
        |> render_click()

      assert html =~ "Viewer banned"
    end

    test "new chat message appears in moderation panel via PubSub", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      viewer = insert(:viewer, organization: org, subscription_status: "active")
      event = insert(:live_event, organization: org, status: "live")

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      assert html =~ ~s(data-test="mod-no-messages")

      {:ok, msg} = Bobine.Streaming.post_chat_message(event, viewer, "new pubsub message!")

      send(
        view.pid,
        {:bobine_event, {:chat_message_posted, msg}, %{organization: org}}
      )

      html = render(view)
      assert html =~ "new pubsub message!"
      assert html =~ ~s(data-test="mod-message-#{msg.id}")
    end
  end

  describe "real-time PubSub updates" do
    test "updates status in real time on live_event_status_changed broadcast", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "scheduled")

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      assert html =~ "Scheduled"

      updated_event = %{event | status: "live"}
      Events.broadcast(nil, {:live_event_status_changed, updated_event})

      html = render(view)
      assert html =~ "Live"
    end

    test "ignores status change broadcast for a different event", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      event = insert(:live_event, organization: org, status: "scheduled")
      other_event = insert(:live_event, organization: org, status: "draft")

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/live-events/#{event.slug}")
      assert html =~ "Scheduled"

      # Broadcast for the OTHER event
      updated_other = %{other_event | status: "canceled"}
      Events.broadcast(nil, {:live_event_status_changed, updated_other})

      html = render(view)
      # Our event's status is unchanged
      assert html =~ "Scheduled"
    end
  end
end
