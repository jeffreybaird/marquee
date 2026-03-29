defmodule BobineWeb.Plugs.SetRequestContext do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    Bobine.RequestContext.put(%{
      request_id: Logger.metadata()[:request_id],
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      scope: conn.assigns[:current_scope]
    })

    conn
  end
end
