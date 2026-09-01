defmodule Marquee.Content.MuxClient do
  @moduledoc """
  Production Mux API client with OpenTelemetry instrumentation.

  Every Mux API call produces a span with the operation name, HTTP status,
  and latency. Returns `{:error, :mux_error, details}` on failure.
  """

  @behaviour Marquee.Content.MuxClientBehaviour

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Mux.Video.Assets
  alias Mux.Video.LiveStreams
  alias Mux.Video.Uploads

  @impl true
  def create_direct_upload(params) do
    Logger.info("Mux create_direct_upload requested",
      org_id: logger_org_id(),
      params: inspect(params, pretty: true, limit: :infinity)
    )

    traced_call("create_direct_upload", fn ->
      Uploads.create(client(), params)
    end)
  end

  @impl true
  def create_audio_direct_upload(params) do
    Logger.info("Mux create_audio_direct_upload requested",
      org_id: logger_org_id(),
      params: inspect(params, pretty: true, limit: :infinity)
    )

    traced_call("create_audio_direct_upload", fn ->
      Uploads.create(client(), params)
    end)
  end

  @impl true
  def get_asset(asset_id) do
    traced_call("get_asset", fn ->
      Assets.get(client(), asset_id)
    end)
  end

  @impl true
  def delete_asset(asset_id) do
    Tracer.with_span "marquee.mux.delete_asset" do
      Tracer.set_attributes([
        {"marquee.mux.operation", "delete_asset"},
        {"marquee.service", "mux"}
        | org_attributes_from_logger()
      ])

      start = System.monotonic_time(:millisecond)

      result = Assets.delete(client(), asset_id)

      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, _, _} ->
          Tracer.set_attribute("http.status_code", 200)
          :ok

        {:error, reason, _} ->
          Tracer.set_status(:error, inspect(reason))

          Logger.error("Mux delete_asset failed",
            org_id: logger_org_id(),
            reason: inspect(reason, pretty: true, limit: :infinity)
          )

          {:error, :mux_error, reason}
      end
    end
  end

  @impl true
  def list_assets(opts \\ []) do
    traced_call("list_assets", fn ->
      Assets.list(client(), opts)
    end)
  end

  @impl true
  def create_live_stream(params) do
    Logger.info("Mux create_live_stream requested",
      org_id: logger_org_id(),
      params: inspect(params, pretty: true, limit: :infinity)
    )

    traced_call("create_live_stream", fn ->
      LiveStreams.create(client(), params)
    end)
  end

  @impl true
  def get_live_stream(stream_id) do
    traced_call("get_live_stream", fn ->
      LiveStreams.get(client(), stream_id)
    end)
  end

  @impl true
  def delete_live_stream(stream_id) do
    Tracer.with_span "marquee.mux.delete_live_stream" do
      Tracer.set_attributes([
        {"marquee.mux.operation", "delete_live_stream"},
        {"marquee.service", "mux"}
        | org_attributes_from_logger()
      ])

      start = System.monotonic_time(:millisecond)
      result = LiveStreams.delete(client(), stream_id)
      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, _, _} ->
          Tracer.set_attribute("http.status_code", 200)
          :ok

        {:error, reason, _} ->
          Tracer.set_status(:error, inspect(reason))

          Logger.error("Mux delete_live_stream failed",
            org_id: logger_org_id(),
            stream_id: stream_id,
            reason: inspect(reason, pretty: true, limit: :infinity)
          )

          {:error, :mux_error, reason}
      end
    end
  end

  @impl true
  def disable_live_stream(stream_id) do
    Tracer.with_span "marquee.mux.disable_live_stream" do
      Tracer.set_attributes([
        {"marquee.mux.operation", "disable_live_stream"},
        {"marquee.service", "mux"}
        | org_attributes_from_logger()
      ])

      start = System.monotonic_time(:millisecond)
      result = LiveStreams.disable(client(), stream_id)
      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, _, _} ->
          Tracer.set_attribute("http.status_code", 200)
          :ok

        {:error, reason, _} ->
          Tracer.set_status(:error, inspect(reason))

          Logger.error("Mux disable_live_stream failed",
            org_id: logger_org_id(),
            stream_id: stream_id,
            reason: inspect(reason, pretty: true, limit: :infinity)
          )

          {:error, :mux_error, reason}
      end
    end
  end

  @impl true
  def enable_live_stream(stream_id) do
    Tracer.with_span "marquee.mux.enable_live_stream" do
      Tracer.set_attributes([
        {"marquee.mux.operation", "enable_live_stream"},
        {"marquee.service", "mux"}
        | org_attributes_from_logger()
      ])

      start = System.monotonic_time(:millisecond)
      result = LiveStreams.enable(client(), stream_id)
      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, _, _} ->
          Tracer.set_attribute("http.status_code", 200)
          :ok

        {:error, reason, _} ->
          Tracer.set_status(:error, inspect(reason))

          Logger.error("Mux enable_live_stream failed",
            org_id: logger_org_id(),
            stream_id: stream_id,
            reason: inspect(reason, pretty: true, limit: :infinity)
          )

          {:error, :mux_error, reason}
      end
    end
  end

  @impl true
  def reset_stream_key(stream_id) do
    traced_call("reset_stream_key", fn ->
      LiveStreams.reset_stream_key(client(), stream_id)
    end)
  end

  defp traced_call(operation, fun) do
    Tracer.with_span "marquee.mux.#{operation}" do
      Tracer.set_attributes([
        {"marquee.mux.operation", operation},
        {"marquee.service", "mux"}
        | org_attributes_from_logger()
      ])

      start = System.monotonic_time(:millisecond)

      result = fun.()

      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, data, _env} ->
          Tracer.set_attribute("http.status_code", 200)

          Logger.info("Mux operation succeeded", org_id: logger_org_id(), operation: operation)

          {:ok, data}

        {:error, type, messages} ->
          Tracer.set_status(:error, inspect(%{type: type, messages: messages}))
          log_mux_validation_failure(operation, type, messages)
          {:error, :mux_error, %{type: type, messages: messages}}
      end
    end
  end

  defp log_mux_validation_failure(operation, type, messages) do
    Logger.error("Mux operation failed",
      org_id: logger_org_id(),
      operation: operation,
      type: inspect(type, pretty: true, limit: :infinity),
      messages: inspect(messages, pretty: true, limit: :infinity)
    )
  end

  defp logger_org_id, do: Logger.metadata()[:org_id]

  defp org_attributes_from_logger do
    case logger_org_id() do
      nil -> []
      org_id -> [{"marquee.org.id", org_id}]
    end
  end

  defp client do
    token_id = Application.fetch_env!(:marquee, :mux_token_id)
    token_secret = Application.fetch_env!(:marquee, :mux_token_secret)
    Mux.client(token_id, token_secret)
  end
end
