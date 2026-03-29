defmodule Bobine.Content.MuxClient do
  @moduledoc """
  Production Mux API client with OpenTelemetry instrumentation.

  Every Mux API call produces a span with the operation name, HTTP status,
  and latency.
  """

  @behaviour Bobine.Content.MuxClientBehaviour

  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def create_upload(params) do
    traced_call("create_upload", fn ->
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
    traced_call("delete_asset", fn ->
      Mux.Video.Assets.delete(client(), asset_id)
    end)
  end

  @impl true
  def create_playback_id(asset_id) do
    traced_call("create_playback_id", fn ->
      Mux.Video.Assets.create_playback_id(client(), asset_id, %{policy: "public"})
    end)
  end

  @impl true
  def delete_playback_id(asset_id, playback_id) do
    traced_call("delete_playback_id", fn ->
      Mux.Video.Assets.delete_playback_id(client(), asset_id, playback_id)
    end)
  end

  @impl true
  def get_asset_input_info(asset_id) do
    traced_call("get_asset_input_info", fn ->
      Mux.Video.Assets.input_info(client(), asset_id)
    end)
  end

  defp traced_call(operation, fun) do
    Tracer.with_span "bobine.mux.#{operation}" do
      Tracer.set_attribute("mux.operation", operation)
      start = System.monotonic_time(:millisecond)

      result = fun.()

      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, _, _} = ok ->
          Tracer.set_attribute("http.status_code", 200)
          {:ok, ok}

        {:ok, _} = ok ->
          Tracer.set_attribute("http.status_code", 200)
          ok

        {:error, reason, _} ->
          Tracer.set_status(:error, inspect(reason))
          {:error, :mux_error, reason}

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
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
