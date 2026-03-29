defmodule Bobine.Content.MuxClient do
  @moduledoc """
  Production Mux API client with OpenTelemetry instrumentation.

  Every Mux API call produces a span with the operation name, HTTP status,
  and latency. Returns `{:error, :mux_error, details}` on failure.
  """

  @behaviour Bobine.Content.MuxClientBehaviour

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def create_direct_upload(params) do
    traced_call("create_direct_upload", fn ->
      Mux.Video.Uploads.create(client(), params)
    end)
  end

  @impl true
  def get_asset(asset_id) do
    traced_call("get_asset", fn ->
      Mux.Video.Assets.get(client(), asset_id)
    end)
  end

  @impl true
  def delete_asset(asset_id) do
    Tracer.with_span "bobine.mux.delete_asset" do
      Tracer.set_attributes([{"mux.operation", "delete_asset"}, {"bobine.service", "mux"}])
      start = System.monotonic_time(:millisecond)

      result = Mux.Video.Assets.delete(client(), asset_id)

      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, _, _} ->
          Tracer.set_attribute("http.status_code", 200)
          :ok

        {:ok, _} ->
          Tracer.set_attribute("http.status_code", 200)
          :ok

        {:error, reason, _} ->
          Tracer.set_status(:error, inspect(reason))
          Logger.error("Mux delete_asset failed", reason: inspect(reason))
          {:error, :mux_error, reason}

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          Logger.error("Mux delete_asset failed", reason: inspect(reason))
          {:error, :mux_error, reason}
      end
    end
  end

  @impl true
  def list_assets(opts \\ []) do
    traced_call("list_assets", fn ->
      Mux.Video.Assets.list(client(), opts)
    end)
  end

  defp traced_call(operation, fun) do
    Tracer.with_span "bobine.mux.#{operation}" do
      Tracer.set_attributes([{"mux.operation", operation}, {"bobine.service", "mux"}])
      start = System.monotonic_time(:millisecond)

      result = fun.()

      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, data, _env} ->
          Tracer.set_attribute("http.status_code", 200)
          Logger.info("Mux #{operation} succeeded", operation: operation)
          {:ok, data}

        {:ok, data} ->
          Tracer.set_attribute("http.status_code", 200)
          Logger.info("Mux #{operation} succeeded", operation: operation)
          {:ok, data}

        {:error, reason, _env} ->
          Tracer.set_status(:error, inspect(reason))
          Logger.error("Mux #{operation} failed", operation: operation, reason: inspect(reason))
          {:error, :mux_error, reason}

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          Logger.error("Mux #{operation} failed", operation: operation, reason: inspect(reason))
          {:error, :mux_error, reason}
      end
    end
  end

  defp client do
    token_id = Application.fetch_env!(:bobine, :mux_token_id)
    token_secret = Application.fetch_env!(:bobine, :mux_token_secret)
    Mux.client(token_id, token_secret)
  end
end
