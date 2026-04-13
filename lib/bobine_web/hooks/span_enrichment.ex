defmodule BobineWeb.Hooks.SpanEnrichment do
  @moduledoc """
  LiveView `on_mount` hook that enriches the current OpenTelemetry span with
  LiveView-specific, tenant, and user attributes for dashboard filtering,
  and mirrors the tenant/user context into `Logger.metadata` so structured
  logs from LiveView event handlers carry `org_id`, `org_slug`, and `user_id`.

  LiveView spans operate over an existing WebSocket connection, so they do not
  carry HTTP semantic convention attributes (`http.route`, `http.method`, etc.).
  This hook adds the attributes that are meaningful for LiveView spans:

    * `bobine.liveview.module` — the LiveView module name
    * `bobine.liveview.connected` — whether this is a connected mount
    * `bobine.org.id` — the current tenant's ID
    * `bobine.org.slug` — the current tenant's slug
    * `bobine.user.id` — the current operator user's ID (if present)

  Must run AFTER `AssignScope` so that `current_scope` is available.
  """

  import Phoenix.LiveView, only: [connected?: 1]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def on_mount(:default, _params, _session, socket) do
    attrs = liveview_attributes(socket) ++ org_attributes(socket) ++ user_attributes(socket)
    safe_set_attributes(attrs)
    put_logger_metadata(socket)
    {:cont, socket}
  end

  defp put_logger_metadata(socket) do
    metadata =
      []
      |> maybe_put(:org_id, socket_org_id(socket))
      |> maybe_put(:org_slug, socket_org_slug(socket))
      |> maybe_put(:user_id, socket_user_id(socket))

    Logger.metadata(metadata)
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  defp socket_org_id(%{assigns: %{current_scope: %{organization: %{id: id}}}})
       when not is_nil(id),
       do: id

  defp socket_org_id(%{assigns: %{organization: %{id: id}}}) when not is_nil(id), do: id
  defp socket_org_id(_), do: nil

  defp socket_org_slug(%{assigns: %{current_scope: %{organization: %{slug: slug}}}})
       when not is_nil(slug),
       do: slug

  defp socket_org_slug(%{assigns: %{organization: %{slug: slug}}}) when not is_nil(slug), do: slug
  defp socket_org_slug(_), do: nil

  defp socket_user_id(%{assigns: %{current_scope: %{user: %{id: id}}}}) when not is_nil(id),
    do: id

  defp socket_user_id(%{assigns: %{current_user: %{id: id}}}) when not is_nil(id), do: id
  defp socket_user_id(_), do: nil

  defp liveview_attributes(socket) do
    view = socket.view |> to_string() |> String.replace("Elixir.", "")

    [
      {"bobine.liveview.module", view},
      {"bobine.liveview.connected", connected?(socket)}
    ]
  end

  defp org_attributes(socket) do
    case socket.assigns do
      %{current_scope: %{organization: %{id: org_id, slug: slug}}} when not is_nil(org_id) ->
        [{"bobine.org.id", org_id}, {"bobine.org.slug", slug}]

      %{organization: %{id: org_id, slug: slug}} when not is_nil(org_id) ->
        [{"bobine.org.id", org_id}, {"bobine.org.slug", slug}]

      _ ->
        []
    end
  end

  defp user_attributes(socket) do
    case socket.assigns do
      %{current_scope: %{user: %{id: user_id}}} when not is_nil(user_id) ->
        [{"bobine.user.id", user_id}]

      %{current_user: %{id: user_id}} when not is_nil(user_id) ->
        [{"bobine.user.id", user_id}]

      _ ->
        []
    end
  end

  defp safe_set_attributes(attrs) do
    Tracer.set_attributes(attrs)
  rescue
    UndefinedFunctionError -> :ok
  end
end
