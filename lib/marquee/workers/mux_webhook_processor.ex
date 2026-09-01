defmodule Marquee.Workers.MuxWebhookProcessor do
  @moduledoc """
  Oban worker that processes Mux webhook events asynchronously.

  Handles video lifecycle events: upload completion, asset readiness, and errors.
  Also handles live stream lifecycle events: active, idle, disconnected, and
  asset.live_stream_completed for recording VOD linking.
  """

  use Oban.Worker,
    queue: :mux,
    unique: [period: 300, fields: [:args], keys: [:payload]]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.Content
  alias Marquee.Podcasts
  alias Marquee.Repo
  alias Marquee.Streaming
  alias Marquee.Streaming.LiveEventNotifier

  @impl true
  def perform(%Oban.Job{args: %{"payload" => payload} = args}) do
    Marquee.Otel.extract_trace_context(args["trace_context"])
    Logger.metadata(event_type: payload["type"], worker: "MuxWebhookProcessor")

    Tracer.with_span "marquee.worker.mux_webhook_processor" do
      Tracer.set_attribute("mux.event_type", payload["type"])
      handle_event(payload["type"], payload["data"])
    end
  end

  # Mux sends "video.upload.asset_created" when the upload is linked to an asset
  defp handle_event("video.upload.asset_created", data) do
    upload_id = data["id"]
    asset_id = data["asset_id"]

    if upload_id && asset_id do
      case Podcasts.link_audio_upload_to_asset(upload_id, asset_id) do
        {:ok, episode} ->
          attribute_to_org(episode)
          :ok

        {:error, :not_found} ->
          dispatch_video_upload_link(upload_id, asset_id)

        {:error, reason} ->
          {:error, reason}
      end
    else
      Logger.warning("Missing upload_id or asset_id in video.upload.asset_created",
        data: inspect(data)
      )

      :ok
    end
  end

  defp handle_event("video.asset.ready", data) do
    asset_id = data["id"]

    if asset_id do
      playback_ids = data["playback_ids"] || []
      public_playback = Enum.find(playback_ids, &(&1["policy"] == "public"))

      static_renditions = data["static_renditions"] || %{}
      mp3_byte_size = mp3_size_from_renditions(static_renditions)

      metadata = %{
        duration: data["duration"],
        max_resolution: data["max_stored_resolution"],
        playback_id: public_playback && public_playback["id"],
        mp3_byte_size: mp3_byte_size
      }

      case Podcasts.mark_episode_ready(asset_id, metadata) do
        {:ok, episode} ->
          attribute_to_org(episode)
          :ok

        {:error, :not_found} ->
          dispatch_video_ready(asset_id, metadata)

        {:error, reason} ->
          {:error, reason}
      end
    else
      Logger.warning("Missing asset_id in video.asset.ready", data: inspect(data))
      :ok
    end
  end

  defp handle_event("video.asset.errored", data) do
    asset_id = data["id"]

    if asset_id do
      error_details = %{
        message: get_in(data, ["errors", "messages"]),
        type: get_in(data, ["errors", "type"])
      }

      Logger.error("Mux asset errored",
        asset_id: asset_id,
        error_details: inspect(error_details, pretty: true, limit: :infinity)
      )

      case Podcasts.mark_episode_errored(asset_id, error_details) do
        {:ok, episode} ->
          attribute_to_org(episode)
          :ok

        {:error, :not_found} ->
          dispatch_video_errored(asset_id, error_details)

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end

  # Live stream active: stream has started receiving video — transition event to :live
  defp handle_event("video.live_stream.active", data) do
    stream_id = data["id"]

    case Streaming.get_live_event_by_mux_stream_id(stream_id) do
      {:ok, event} ->
        attribute_to_org(event)
        # Build a system scope to drive the transition
        scope = %Scope{organization: %{id: event.organization_id}}

        case Streaming.transition_event(scope, event, "live") do
          {:ok, updated} ->
            Logger.info("Live event transitioned to live",
              org_id: event.organization_id,
              live_event_id: event.id
            )

            attribute_to_org(updated)
            org = Repo.get!(Organization, updated.organization_id)
            LiveEventNotifier.send_live_now_emails(updated, org)
            :ok

          {:error, :invalid_transition} ->
            # Already live or in a terminal state — idempotent, not an error
            Logger.debug("Live stream active: transition already applied or invalid",
              org_id: event.organization_id,
              live_event_id: event.id,
              current_status: event.status
            )

            :ok

          {:error, :validation, _cs} = err ->
            err
        end

      {:error, :not_found} ->
        Logger.debug("video.live_stream.active: no live event for stream",
          stream_id: stream_id
        )

        :ok
    end
  end

  # Live stream idle: stream is no longer receiving video — if it was live, transition to ended
  defp handle_event("video.live_stream.idle", data) do
    stream_id = data["id"]

    case Streaming.get_live_event_by_mux_stream_id(stream_id) do
      {:ok, %{status: "live"} = event} ->
        attribute_to_org(event)
        scope = %Scope{organization: %{id: event.organization_id}}

        case Streaming.transition_event(scope, event, "ended") do
          {:ok, updated} ->
            Logger.info("Live event transitioned to ended",
              org_id: event.organization_id,
              live_event_id: event.id
            )

            attribute_to_org(updated)
            :ok

          {:error, :validation, _cs} = err ->
            err
        end

      {:ok, event} ->
        # Event not in live status — log and ignore
        Logger.debug("video.live_stream.idle: event not live, no transition",
          org_id: event.organization_id,
          live_event_id: event.id,
          current_status: event.status
        )

        :ok

      {:error, :not_found} ->
        Logger.debug("video.live_stream.idle: no live event for stream",
          stream_id: stream_id
        )

        :ok
    end
  end

  # Live stream disconnected: broadcaster lost connection — do NOT end the event,
  # wait for idle which fires after reconnect_window expires
  defp handle_event("video.live_stream.disconnected", data) do
    stream_id = data["id"]

    case Streaming.get_live_event_by_mux_stream_id(stream_id) do
      {:ok, event} ->
        attribute_to_org(event)

        Logger.info("Live stream disconnected (waiting for idle or reconnect)",
          org_id: event.organization_id,
          live_event_id: event.id,
          stream_id: stream_id
        )

        :ok

      {:error, :not_found} ->
        Logger.debug("video.live_stream.disconnected: no live event for stream",
          stream_id: stream_id
        )

        :ok
    end
  end

  # Recording available for future use (not yet implemented)
  defp handle_event("video.live_stream.recording.ready", _data) do
    :ok
  end

  # Live stream completed: Mux has finished processing the recording asset.
  # Link the new VOD asset to the live event.
  defp handle_event("video.asset.live_stream_completed", data) do
    asset_id = data["id"]
    stream_id = data["live_stream_id"]

    if asset_id && stream_id do
      Logger.info("Live stream recording asset ready",
        stream_id: stream_id,
        mux_asset_id: asset_id
      )

      Streaming.handle_recording_completed(stream_id, data)
    else
      Logger.warning("Missing asset_id or live_stream_id in video.asset.live_stream_completed",
        data: inspect(data)
      )

      :ok
    end
  end

  defp handle_event(type, _data) do
    Logger.debug("Unhandled Mux webhook event", type: type)
    :ok
  end

  defp dispatch_video_upload_link(upload_id, asset_id) do
    case Content.link_upload_to_asset(upload_id, asset_id) do
      {:ok, video} ->
        attribute_to_org(video)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch_video_ready(asset_id, metadata) do
    case Content.mark_video_ready(asset_id, metadata) do
      {:ok, video} ->
        attribute_to_org(video)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch_video_errored(asset_id, error_details) do
    case Content.mark_video_errored(asset_id, error_details) do
      {:ok, video} ->
        attribute_to_org(video)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mp3_size_from_renditions(%{"files" => files}) when is_list(files) do
    Enum.find_value(files, fn
      %{"ext" => "mp3", "filesize" => size} when is_integer(size) -> size
      %{"ext" => "mp3", "filesize" => size} when is_binary(size) -> String.to_integer(size)
      _ -> nil
    end)
  end

  defp mp3_size_from_renditions(_), do: nil

  defp attribute_to_org(%{organization_id: org_id}) when not is_nil(org_id) do
    Logger.metadata(org_id: org_id)
    Tracer.set_attributes([{"marquee.org.id", org_id}])
  end

  defp attribute_to_org(_), do: :ok
end
