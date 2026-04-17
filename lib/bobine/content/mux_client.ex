defmodule Bobine.Content.MuxClient do
  @moduledoc """
  Production Mux API client with OpenTelemetry instrumentation.

  Every Mux API call produces a span with the operation name, HTTP status,
  and latency. Returns `{:error, :mux_error, details}` on failure.
  """

  @behaviour Bobine.Content.MuxClientBehaviour

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Mux.Video.Assets
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
  def get_asset(asset_id) do
    traced_call("get_asset", fn ->
      Assets.get(client(), asset_id)
    end)
  end

  @impl true
  def delete_asset(asset_id) do
    Tracer.with_span "bobine.mux.delete_asset" do
      Tracer.set_attributes([
        {"bobine.mux.operation", "delete_asset"},
        {"bobine.service", "mux"}
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

  defp traced_call(operation, fun) do
    Tracer.with_span "bobine.mux.#{operation}" do
      Tracer.set_attributes([
        {"bobine.mux.operation", operation},
        {"bobine.service", "mux"}
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
      org_id -> [{"bobine.org.id", org_id}]
    end
  end

  defp client do
    token_id = Application.fetch_env!(:bobine, :mux_token_id)
    token_secret = Application.fetch_env!(:bobine, :mux_token_secret)
    Mux.client(token_id, token_secret)
  end
end
