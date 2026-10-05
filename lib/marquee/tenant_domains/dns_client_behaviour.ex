defmodule Marquee.TenantDomains.DNSClientBehaviour do
  @moduledoc "Boundary for idempotent managed DNS reconciliation."
  @callback ensure_record(String.t(), String.t(), String.t()) ::
              {:ok, %{id: String.t() | integer()}} | {:error, atom()}
end
