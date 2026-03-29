defmodule Bobine.Workers.MuxAssetCleanup do
  @moduledoc """
  Oban worker that deletes a Mux asset when a video is soft-deleted.
  """

  use Oban.Worker, queue: :mux

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"mux_asset_id" => asset_id, "organization_id" => org_id}}) do
    Logger.metadata(org_id: org_id)
    Logger.info("Cleaning up Mux asset", asset_id: asset_id)

    case mux_client().delete_asset(asset_id) do
      :ok -> :ok
      {:error, :mux_error, _reason} -> :ok
    end
  end

  defp mux_client do
    Application.get_env(:bobine, :mux_client, Bobine.Content.MuxClient)
  end
end
