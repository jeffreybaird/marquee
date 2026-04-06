defmodule BobineWeb.Hooks.SpanEnrichment do
  @moduledoc """
  LiveView `on_mount` hook that enriches the current OpenTelemetry span with
  LiveView-specific, tenant, and user attributes for dashboard filtering.

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

  require OpenTelemetry.Tracer, as: Tracer

  def on_mount(:default, _params, _session, socket) do
    attrs = liveview_attributes(socket) ++ org_attributes(socket) ++ user_attributes(socket)
    safe_set_attributes(attrs)
    {:cont, socket}
  end

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
