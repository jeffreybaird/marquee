defmodule MarqueeWeb.Plugs.SetRequestContext do
  @moduledoc false

  require Logger

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]

    # Set Logger metadata for structured logging with trace context
    Logger.metadata(
      org_id: scope_org_id(scope),
      org_slug: scope_org_slug(scope),
      user_id: scope_user_id(scope)
    )

    Marquee.RequestContext.put(%{
      request_id: Logger.metadata()[:request_id],
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      scope: scope
    })

    conn
  end

  defp scope_org_id(%{organization: %{id: id}}), do: id
  defp scope_org_id(_), do: nil

  defp scope_org_slug(%{organization: %{slug: slug}}), do: slug
  defp scope_org_slug(_), do: nil

  defp scope_user_id(%{user: %{id: id}}), do: id
  defp scope_user_id(_), do: nil
end
