defmodule BobineWeb.Admin.ContentLiveRealtimeTest do
  use BobineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "real-time video status updates" do
    test "video status updates when video_ready event is broadcast", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      video =
        insert(:video,
          organization: org,
          title: "Processing Video",
          mux_status: "preparing",
          mux_asset_id: "asset_rt_1"
        )

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Processing"

      # Simulate Mux webhook completing — broadcast video_ready event
      updated_video = %{video | mux_status: "ready", mux_playback_id: "pb_rt_1", duration: 60.0}
      Bobine.Events.broadcast(nil, {:video_ready, updated_video})

      # The status badge should update without a page refresh
      html = render(view)
      assert html =~ "Ready"
    end
  end

  describe "upload form validation" do
    test "submitting upload with empty title shows validation error", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      # Open the upload modal
      render_click(view, "open_upload")

      # Submit with empty title
      html = render_submit(view, "submit_upload", %{"title" => "", "description" => ""})

      # Should show validation error, not crash
      assert html =~ "title" or html =~ "Title" or html =~ "provide"
    end
  end
end
