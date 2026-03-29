defmodule BobineWeb.Viewer.WatchLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /watch/:id" do
    test "renders video title and player element", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      video =
        insert(:video,
          organization: org,
          title: "My Great Video",
          mux_status: "ready",
          mux_playback_id: "playback_abc"
        )

      {:ok, _view, html} = live(conn_for(membership), ~p"/watch/#{video.id}")
      assert html =~ "My Great Video"
      assert html =~ ~s(data-test="player-container")
      assert html =~ "playback_abc"
    end

    test "non-existent video redirects to home", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for(membership), ~p"/watch/#{Ecto.UUID.generate()}")
    end

    test "video with status != ready redirects to home", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      video = insert(:video, organization: org, mux_status: "preparing")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for(membership), ~p"/watch/#{video.id}")
    end

    test "video from another org returns not found (redirects)", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      video = insert(:video, organization: other_org, mux_status: "ready")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn_for(membership), ~p"/watch/#{video.id}")
    end

    test "player has correct data-resume-position when no progress", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user)

      video =
        insert(:video,
          organization: org,
          mux_status: "ready",
          mux_playback_id: "pb_1"
        )

      {:ok, _view, html} = live(conn_for(membership), ~p"/watch/#{video.id}")
      assert html =~ ~s(data-resume-position="0.0")
    end
  end
end
