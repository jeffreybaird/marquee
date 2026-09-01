defmodule MarqueeWeb.Hooks.RequireSubscriptionTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "require_subscription via /watch/:id" do
    test "subscribed viewer can access watch page", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org)

      video =
        insert(:video,
          organization: org,
          mux_status: "ready",
          mux_playback_id: "pb_test",
          visibility: "subscribers_only"
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/watch/#{video.id}")
      assert html =~ video.title
    end

    test "unsubscribed viewer redirected to /subscribe", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, subscription_status: "none")

      assert {:error, {:redirect, %{to: "/subscribe"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{Ecto.UUID.generate()}")
    end

    test "suspended viewer redirected to /", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org, status: :suspended)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{Ecto.UUID.generate()}")
    end

    test "banned viewer redirected to /", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:subscribed_viewer, organization: org, status: :banned)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn_for_viewer(viewer), ~p"/watch/#{Ecto.UUID.generate()}")
    end
  end
end
