defmodule Bobine.Workers.MuxWebhookProcessorTest do
  use Bobine.DataCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  import Mox

  alias Bobine.Content
  alias Bobine.Streaming
  alias Bobine.Workers.MuxWebhookProcessor

  setup :verify_on_exit!

  describe "video.upload.asset_created" do
    test "links upload to asset and sets status to preparing" do
      org = insert(:organization)

      video =
        insert(:video,
          organization: org,
          mux_upload_id: "upload_xyz",
          mux_status: "waiting",
          mux_asset_id: nil
        )

      payload = %{
        "type" => "video.upload.asset_created",
        "data" => %{"id" => "upload_xyz", "asset_id" => "asset_abc"}
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      updated = Content.get_video!(org, video.id)
      assert updated.mux_asset_id == "asset_abc"
      assert updated.mux_status == "preparing"
    end
  end

  describe "video.asset.ready" do
    test "updates video status and stores metadata" do
      org = insert(:organization)

      video =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_123",
          mux_status: "preparing"
        )

      payload = %{
        "type" => "video.asset.ready",
        "data" => %{
          "id" => "asset_123",
          "duration" => 125.5,
          "max_stored_resolution" => "1080p",
          "playback_ids" => [%{"id" => "playback_abc", "policy" => "public"}]
        }
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      updated = Content.get_video!(org, video.id)
      assert updated.mux_status == "ready"
      assert updated.duration == 125.5
      assert updated.max_resolution == "1080p"
      assert updated.mux_playback_id == "playback_abc"
    end
  end

  describe "video.asset.errored" do
    test "marks video as errored" do
      org = insert(:organization)

      video =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_456",
          mux_status: "preparing"
        )

      payload = %{
        "type" => "video.asset.errored",
        "data" => %{
          "id" => "asset_456",
          "errors" => %{"messages" => ["encode failed"], "type" => "internal"}
        }
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      updated = Content.get_video!(org, video.id)
      assert updated.mux_status == "errored"
    end
  end

  describe "podcast audio routing" do
    alias Bobine.Podcasts

    test "video.upload.asset_created routes to a podcast episode when one owns the upload" do
      org = insert(:organization)
      show = insert(:podcast_show, organization: org)

      ep =
        insert(:podcast_episode,
          organization: org,
          show: show,
          mux_upload_id: "upload_pod",
          mux_asset_id: nil,
          mux_status: "waiting"
        )

      payload = %{
        "type" => "video.upload.asset_created",
        "data" => %{"id" => "upload_pod", "asset_id" => "asset_pod"}
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      {:ok, updated} = Podcasts.get_episode(org, ep.id)
      assert updated.mux_asset_id == "asset_pod"
      assert updated.mux_status == "preparing"
    end

    test "video.asset.ready publishes the podcast episode and stores mp3 size" do
      org = insert(:organization)
      show = insert(:podcast_show, organization: org)

      ep =
        insert(:podcast_episode,
          organization: org,
          show: show,
          mux_asset_id: "asset_pod_ready",
          mux_status: "preparing",
          status: "processing"
        )

      payload = %{
        "type" => "video.asset.ready",
        "data" => %{
          "id" => "asset_pod_ready",
          "duration" => 90.0,
          "playback_ids" => [%{"id" => "pb_pod", "policy" => "public"}],
          "static_renditions" => %{
            "files" => [%{"ext" => "mp3", "filesize" => 12_345_678}]
          }
        }
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      {:ok, updated} = Podcasts.get_episode(org, ep.id)
      assert updated.mux_status == "ready"
      assert updated.status == "published"
      assert updated.mp3_byte_size == 12_345_678
      assert updated.mux_playback_id == "pb_pod"
    end

    test "video.asset.ready falls through to Content when no podcast episode owns the asset" do
      org = insert(:organization)

      video =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_fall_through",
          mux_status: "preparing"
        )

      payload = %{
        "type" => "video.asset.ready",
        "data" => %{
          "id" => "asset_fall_through",
          "duration" => 30.0,
          "max_stored_resolution" => "720p",
          "playback_ids" => [%{"id" => "pb_v", "policy" => "public"}]
        }
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      updated = Content.get_video!(org, video.id)
      assert updated.mux_status == "ready"
    end

    test "video.asset.errored marks the podcast episode errored" do
      org = insert(:organization)
      show = insert(:podcast_show, organization: org)

      ep =
        insert(:podcast_episode,
          organization: org,
          show: show,
          mux_asset_id: "asset_pod_err",
          mux_status: "preparing",
          status: "processing"
        )

      payload = %{
        "type" => "video.asset.errored",
        "data" => %{
          "id" => "asset_pod_err",
          "errors" => %{"messages" => ["bad mp3"], "type" => "internal"}
        }
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      {:ok, updated} = Podcasts.get_episode(org, ep.id)
      assert updated.mux_status == "errored"
      assert updated.error_message == "bad mp3"
    end
  end

  describe "idempotency" do
    test "processing same webhook twice produces same result" do
      org = insert(:organization)

      insert(:video,
        organization: org,
        mux_asset_id: "asset_789",
        mux_status: "preparing"
      )

      payload = %{
        "type" => "video.asset.ready",
        "data" => %{
          "id" => "asset_789",
          "duration" => 60.0,
          "max_stored_resolution" => "720p",
          "playback_ids" => [%{"id" => "pb_xyz", "policy" => "public"}]
        }
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})
      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})
    end
  end

  describe "unknown event" do
    test "handles gracefully" do
      payload = %{
        "type" => "video.something.unknown",
        "data" => %{}
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})
    end
  end

  ## ---------------------------------------------------------------------------
  ## Live stream webhook handlers
  ## ---------------------------------------------------------------------------

  describe "video.live_stream.active" do
    test "transitions scheduled event to live" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          mux_live_stream_id: "stream_live_1"
        )

      payload = %{
        "type" => "video.live_stream.active",
        "data" => %{"id" => "stream_live_1"}
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      assert {:ok, updated} = Streaming.get_live_event(org, event.id)
      assert updated.status == "live"
      assert updated.went_live_at != nil
    end

    test "idempotent: already live event stays live" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          mux_live_stream_id: "stream_live_2"
        )

      payload = %{
        "type" => "video.live_stream.active",
        "data" => %{"id" => "stream_live_2"}
      }

      # Should not error even though transition is invalid (already live)
      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      assert {:ok, still_live} = Streaming.get_live_event(org, event.id)
      assert still_live.status == "live"
    end

    test "no-op when no event found for stream" do
      payload = %{
        "type" => "video.live_stream.active",
        "data" => %{"id" => "unknown_stream_id"}
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})
    end
  end

  describe "video.live_stream.idle" do
    test "transitions live event to ended" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "live",
          mux_live_stream_id: "stream_idle_1"
        )

      payload = %{
        "type" => "video.live_stream.idle",
        "data" => %{"id" => "stream_idle_1"}
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      assert {:ok, updated} = Streaming.get_live_event(org, event.id)
      assert updated.status == "ended"
      assert updated.ended_at != nil
    end

    test "no-op when event is not live" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          mux_live_stream_id: "stream_idle_2"
        )

      payload = %{
        "type" => "video.live_stream.idle",
        "data" => %{"id" => "stream_idle_2"}
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      assert {:ok, unchanged} = Streaming.get_live_event(org, event.id)
      assert unchanged.status == "scheduled"
    end
  end

  describe "video.live_stream.disconnected" do
    test "logs disconnect but does NOT end the event" do
      org = insert(:organization)

      event =
        insert(:live_event, organization: org, status: "live", mux_live_stream_id: "stream_dc_1")

      payload = %{
        "type" => "video.live_stream.disconnected",
        "data" => %{"id" => "stream_dc_1"}
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      # Event should remain live — disconnect waits for idle
      assert {:ok, still_live} = Streaming.get_live_event(org, event.id)
      assert still_live.status == "live"
    end
  end

  describe "video.asset.live_stream_completed" do
    test "links recording asset to live event" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "ended",
          mux_live_stream_id: "stream_completed_1"
        )

      payload = %{
        "type" => "video.asset.live_stream_completed",
        "data" => %{
          "id" => "asset_rec_001",
          "live_stream_id" => "stream_completed_1",
          "playback_ids" => [%{"id" => "pb_rec_001", "policy" => "public"}],
          "duration" => 3600.0
        }
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      assert {:ok, updated} = Streaming.get_live_event(org, event.id)
      assert updated.recording_video_id != nil
    end

    test "idempotency: same event delivered twice produces no error" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "ended",
          mux_live_stream_id: "stream_completed_2"
        )

      payload = %{
        "type" => "video.asset.live_stream_completed",
        "data" => %{
          "id" => "asset_rec_002",
          "live_stream_id" => "stream_completed_2",
          "playback_ids" => []
        }
      }

      # First delivery — links recording
      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})
      # Second delivery — idempotent no-op, must not error or create duplicate
      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})

      assert {:ok, updated} = Streaming.get_live_event(org, event.id)
      assert updated.recording_video_id != nil
    end

    test "no-op when no live event found for stream" do
      payload = %{
        "type" => "video.asset.live_stream_completed",
        "data" => %{
          "id" => "asset_orphan",
          "live_stream_id" => "stream_nonexistent"
        }
      }

      assert :ok = perform_job(MuxWebhookProcessor, %{"payload" => payload})
    end
  end
end
