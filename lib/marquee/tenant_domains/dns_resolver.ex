defmodule Marquee.TenantDomains.DNSResolver do
  @moduledoc "Reads public A and AAAA answers before initiating a readiness probe."

  @doc "Resolves both address families through the system resolver. Performs external DNS lookups."
  def resolve(hostname) do
    with {:ok, a} <- addresses(hostname, :inet),
         {:ok, aaaa} <- addresses(hostname, :inet6) do
      {:ok, %{a: a, aaaa: aaaa}}
    end
  end

  defp addresses(host, family) do
    case :inet.getaddrs(String.to_charlist(host), family) do
      {:ok, values} -> {:ok, Enum.map(values, &(&1 |> :inet.ntoa() |> to_string()))}
      {:error, :nxdomain} -> {:ok, []}
      _ -> {:error, :dns_pending}
    end
  end
end
