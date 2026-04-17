defmodule Bobine.Workers.AuditLogExporter do
  @moduledoc """
  Oban worker that exports audit logs to CSV and uploads to DigitalOcean Spaces.

  Broadcasts completion (or failure) on `"audit-exports:{user_id}"` via PubSub so
  the operator LiveView can display a download link without polling.

  Args:
  - `organization_id` — the org's ID, or nil for platform-wide exports
  - `scope` — `"org"` or `"platform"`
  - `filters` — map of filter params (action, user_id, resource_type, from, to, search)
  - `user_id` — the requesting user's ID (for PubSub delivery)
  - `format` — `"csv"` (only supported format currently)
  """

  use Oban.Worker, queue: :bulk, max_attempts: 3

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Bobine.Repo
  alias Bobine.Storage

  @csv_columns ~w[timestamp actor_email action resource_type resource_id organization_slug metadata_json]

  @impl true
  def perform(%Oban.Job{
        args: %{"user_id" => user_id} = args,
        attempt: attempt
      }) do
    Bobine.Otel.extract_trace_context(args["trace_context"])

    org_id = args["organization_id"]
    scope = args["scope"] || "org"
    filters = parse_filters(args["filters"] || %{})

    Logger.metadata(
      org_id: org_id,
      worker: "AuditLogExporter"
    )

    Tracer.with_span "bobine.worker.audit_log_exporter" do
      Tracer.set_attributes([
        {"bobine.org.id", org_id},
        {"bobine.worker", "AuditLogExporter"},
        {"oban.queue", "bulk"},
        {"oban.attempt", attempt}
      ])

      case build_and_upload_csv(scope, org_id, filters) do
        {:ok, url} ->
          broadcast_ready(user_id, url)
          Logger.info("Audit log export complete", user_id: user_id)
          :ok

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          broadcast_failed(user_id, reason)
          Logger.error("Audit log export failed", user_id: user_id, reason: inspect(reason))
          {:error, reason}
      end
    end
  end

  defp build_and_upload_csv(scope, org_id, filters) do
    key = export_key(org_id)
    csv_data = build_csv(scope, org_id, filters)

    case Storage.put_object(key, csv_data, "text/csv") do
      :ok -> {:ok, Storage.public_url_for_key(key)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_csv(scope, org_id, filters) do
    header = Enum.join(@csv_columns, ",")

    rows =
      Repo.transaction(fn ->
        stream_query(scope, org_id, filters)
        |> Repo.stream(max_rows: 500)
        |> Stream.map(&log_to_csv_row/1)
        |> Enum.to_list()
      end)

    case rows do
      {:ok, data_rows} ->
        ([header] ++ data_rows) |> Enum.join("\n")

      {:error, reason} ->
        raise "Failed to stream audit logs: #{inspect(reason)}"
    end
  end

  defp stream_query("org", org_id, filters) when is_binary(org_id) do
    import Ecto.Query
    alias Bobine.Accounts.{Organization, User}
    alias Bobine.Audit.Log

    Log
    |> where([l], l.organization_id == ^org_id)
    |> apply_stream_filters(filters)
    |> join(:left, [l], u in User, on: l.user_id == u.id)
    |> join(:left, [l, _u], o in Organization, on: l.organization_id == o.id)
    |> select([l, u, o], %{
      inserted_at: l.inserted_at,
      action: l.action,
      resource_type: l.resource_type,
      resource_id: l.resource_id,
      metadata: l.metadata,
      actor_email: u.email,
      org_slug: o.slug
    })
    |> order_by([l], desc: l.inserted_at, desc: l.id)
  end

  defp stream_query(_scope, _org_id, filters) do
    import Ecto.Query
    alias Bobine.Accounts.{Organization, User}
    alias Bobine.Audit.Log

    Log
    |> apply_stream_filters(filters)
    |> join(:left, [l], u in User, on: l.user_id == u.id)
    |> join(:left, [l, _u], o in Organization, on: l.organization_id == o.id)
    |> select([l, u, o], %{
      inserted_at: l.inserted_at,
      action: l.action,
      resource_type: l.resource_type,
      resource_id: l.resource_id,
      metadata: l.metadata,
      actor_email: u.email,
      org_slug: o.slug
    })
    |> order_by([l], desc: l.inserted_at, desc: l.id)
  end

  defp apply_stream_filters(query, filters) do
    import Ecto.Query

    query
    |> maybe_filter(:action, filters["action"])
    |> maybe_filter(:user_id, filters["user_id"])
    |> maybe_filter(:resource_type, filters["resource_type"])
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query

  defp maybe_filter(query, field, value) do
    import Ecto.Query
    where(query, [l], field(l, ^field) == ^value)
  end

  defp log_to_csv_row(%{} = log) do
    [
      format_timestamp(log.inserted_at),
      escape_csv(log.actor_email || ""),
      escape_csv(log.action),
      escape_csv(log.resource_type),
      escape_csv(to_string(log.resource_id || "")),
      escape_csv(log.org_slug || ""),
      escape_csv(Jason.encode!(log.metadata))
    ]
    |> Enum.join(",")
  end

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_timestamp(nil), do: ""

  defp escape_csv(nil), do: ""

  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      ~s("#{String.replace(value, "\"", "\"\"")}")
    else
      value
    end
  end

  defp export_key(nil) do
    uuid = Ecto.UUID.generate()
    "exports/audit/platform/#{uuid}.csv"
  end

  defp export_key(org_id) do
    uuid = Ecto.UUID.generate()
    "exports/audit/#{org_id}/#{uuid}.csv"
  end

  defp parse_filters(filters) when is_map(filters), do: filters

  defp broadcast_ready(user_id, url) do
    Phoenix.PubSub.broadcast(
      Bobine.PubSub,
      "audit-exports:#{user_id}",
      {:audit_export_ready, url}
    )
  end

  defp broadcast_failed(user_id, reason) do
    Phoenix.PubSub.broadcast(
      Bobine.PubSub,
      "audit-exports:#{user_id}",
      {:audit_export_failed, inspect(reason)}
    )
  end
end
