defmodule Marquee.TenantDomains.ReadinessProbe do
  @moduledoc "Verifies public DNS and an HTTPS response from the expected allocation generation."
  @behaviour Marquee.TenantDomains.ProbeBehaviour
  require Marquee.Otel

  @doc "Checks DNS, trusted TLS and the exact application identity without following redirects. Performs external requests."
  @impl true
  def check(hostname, target, identity) do
    Marquee.Otel.with_span "marquee.tenant_domains.readiness_probe" do
      resolver =
        Application.get_env(:marquee, :tenant_dns_resolver, Marquee.TenantDomains.DNSResolver)

      case resolver.resolve(hostname) do
        {:ok, %{a: [_ | _] = addresses, aaaa: []}} ->
          if Enum.all?(addresses, &(&1 == target)),
            do: verify_https(hostname, identity),
            else: {:error, :dns_pending}

        _ ->
          {:error, :dns_pending}
      end
    end
  end

  defp verify_https(hostname, identity) do
    opts = Application.get_env(:marquee, :tenant_probe_req_options, [])

    opts =
      Keyword.merge(opts,
        url: "https://#{hostname}/.well-known/marquee-domain",
        retry: false,
        redirect: false,
        receive_timeout: 15_000,
        connect_options: [timeout: 10_000, transport_opts: [verify: :verify_peer]]
      )

    case Req.get(opts) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        if body["hostname"] == hostname and body["domain_id"] == identity.domain_id and
             body["generation"] == identity.generation, do: :ok, else: {:error, :tls_pending}

      _ ->
        {:error, :tls_pending}
    end
  end
end
