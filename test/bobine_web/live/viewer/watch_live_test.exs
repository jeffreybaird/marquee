defmodule BobineWeb.Viewer.WatchLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /watch/:id with subscribed viewer" do
    test "renders video title and player element", %{conn: _conn} do
      org = insert(:organization)

      viewer =
        insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "My Great Video",
          mux_status: "ready",
          mux_playback_id: "playback_abc",
          visibility: "subscribers_only"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ "My Great Video"
      assert html =~ ~s(data-test="player-container")
      assert html =~ "playback_abc"
    end

    test "non-existent video redirects to home", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{Ecto.UUID.generate()}")
    end

    test "video with status != ready redirects to home", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video = insert(:video, organization: org, mux_status: "preparing")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
    end

    test "video from another org returns not found (redirects)", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video = insert(:video, organization: other_org, mux_status: "ready")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
    end

    test "player has correct data-resume-position when no progress", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          mux_status: "ready",
          mux_playback_id: "pb_1",
          visibility: "subscribers_only"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ ~s(data-resume-position="0.0")
    end

    test "public video accessible to subscribed viewer", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready", visibility: "public")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ video.title
    end
  end

  describe "visibility gating" do
    test "unsubscribed viewer redirected to /subscribe by RequireSubscription hook", %{
      conn: _conn
    } do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      assert {:error, {:redirect, %{to: "/subscribe"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{Ecto.UUID.generate()}")
    end

    test "suspended viewer cannot access watch page", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org, status: :suspended)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{Ecto.UUID.generate()}")
    end

    test "banned viewer cannot access watch page", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org, status: :banned)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{Ecto.UUID.generate()}")
    end
  end
end
