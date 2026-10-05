defmodule MarqueeWeb.TenantDomainController do
  @moduledoc "Read-only certificate permission and application readiness endpoints."
  use MarqueeWeb, :controller
  alias Marquee.TenantDomains

  @doc "Authorizes only eligible persisted managed hostnames. Reads database state; never provisions."
  def ask(conn, params) do
    status = if TenantDomains.allowed_hostname?(params["domain"]), do: 200, else: 403
    send_resp(conn, status, "")
  end

  @doc "Returns the allocation identity for a verified readiness probe. Reads database state."
  def health(conn, _params) do
    case TenantDomains.find_hostname(conn.host, [:dns_ready, :ready]) do
      nil ->
        send_resp(conn, 404, "Not found")

      domain ->
        json(conn, %{
          hostname: domain.hostname,
          domain_id: domain.id,
          generation: domain.generation
        })
    end
  end
end
