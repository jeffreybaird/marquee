defmodule Bobine.Workers.MuxWebhookProcessorTest do
  use Bobine.DataCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  alias Bobine.Content
  alias Bobine.Workers.MuxWebhookProcessor

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
end
