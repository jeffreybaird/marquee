defmodule MarqueeWeb.Viewer.SubscriberDemoPlaybackSecurityTest do
  use MarqueeWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Marquee.Buffers.ProgressBuffer
  alias Marquee.{Engagement, Repo, Viewers}

  test "playback events cannot write activity for another tenant or an unmounted video" do
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})

    mounted =
      insert(:video, organization: org, published: true, mux_status: "ready", duration: 180.0)

    unmounted =
      insert(:video, organization: org, published: true, mux_status: "ready", duration: 180.0)

    foreign =
      insert(:video,
        organization: insert(:organization),
        published: true,
        mux_status: "ready",
        duration: 180.0
      )

    conn = build_conn() |> Map.put(:host, "the-workshop.localhost") |> post("/demo/subscriber")
    viewer = Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token))
    {:ok, watch, _} = live(recycle(conn), "/watch/#{mounted.id}")

    for target <- [foreign, unmounted], event <- ["playback_progress", "playback_paused"] do
      before = Engagement.get_progress(org, viewer, target)
      render_click(watch, event, %{"video_id" => target.id, "position" => 81})
      assert Engagement.get_progress(org, viewer, target) == before

      refute Enum.any?(
               ProgressBuffer.list_viewer_entries(org.id, viewer.id),
               &(&1.video_id == target.id && &1.position == 81)
             )
    end

    for target <- [foreign, unmounted] do
      render_click(watch, "playback_drop_off", %{
        "video_id" => target.id,
        "max_position" => 81,
        "video_duration" => 180
      })

      refute Repo.exists?(
               from d in Marquee.Engagement.PlaybackDropOff,
                 where: d.viewer_id == ^viewer.id and d.video_id == ^target.id
             )
    end
  end
end
