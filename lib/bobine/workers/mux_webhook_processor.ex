defmodule Bobine.Workers.MuxWebhookProcessor do
  @moduledoc """
  Oban worker that processes Mux webhook events asynchronously.

  Handles video lifecycle events: upload completion, asset readiness, and errors.
  """

  use Oban.Worker,
    queue: :mux,
    unique: [period: 60, fields: [:args], keys: [:payload]]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Bobine.Content

  @impl true
  def perform(%Oban.Job{args: %{"payload" => payload} = args}) do
    Bobine.Otel.extract_trace_context(args["trace_context"])
    Logger.metadata(event_type: payload["type"], worker: "MuxWebhookProcessor")

    Tracer.with_span "bobine.worker.mux_webhook_processor" do
      Tracer.set_attribute("mux.event_type", payload["type"])
      handle_event(payload["type"], payload["data"])
    end
  end

  # Mux sends "video.upload.asset_created" when the upload is linked to an asset
  defp handle_event("video.upload.asset_created", data) do
    upload_id = data["id"]
    asset_id = data["asset_id"]

    if upload_id && asset_id do
      case Content.link_upload_to_asset(upload_id, asset_id) do
        {:ok, _video} -> :ok
        {:error, reason} -> {:error, reason}
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

      metadata = %{
        duration: data["duration"],
        max_resolution: data["max_stored_resolution"],
        playback_id: public_playback && public_playback["id"]
      }

      case Content.mark_video_ready(asset_id, metadata) do
        {:ok, _video} -> :ok
        {:error, reason} -> {:error, reason}
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

      case Content.mark_video_errored(asset_id, error_details) do
        {:ok, _video} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp handle_event(type, _data) do
    Logger.debug("Unhandled Mux webhook event", type: type)
    :ok
  end
end
