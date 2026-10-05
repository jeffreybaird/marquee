defmodule Marquee.Workers.MuxAssetCleanup do
  @moduledoc """
  Oban worker that deletes a Mux asset when a video is soft-deleted.
  """

  use Oban.Worker, queue: :mux

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def perform(%Oban.Job{
        args: %{"mux_asset_id" => asset_id, "organization_id" => org_id} = args
      }) do
    with :ok <-
           Marquee.AdminDemo.worker_permission(
             if(Marquee.AdminDemo.protected_asset?(asset_id),
               do: {:error, :demo_forbidden},
               else: Marquee.AdminDemo.external_effect(org_id)
             )
           ) do
      Marquee.Otel.extract_trace_context(args["trace_context"])
      Logger.metadata(org_id: org_id, worker: "MuxAssetCleanup")
      Tracer.set_attributes([{"marquee.org.id", org_id}])
      Logger.info("Cleaning up Mux asset", asset_id: asset_id)

      case mux_client().delete_asset(asset_id) do
        :ok -> :ok
        {:error, :mux_error, _reason} -> :ok
      end
    end
  end

  defp mux_client do
    Application.get_env(:marquee, :mux_client, Marquee.Content.MuxClient)
  end
end
