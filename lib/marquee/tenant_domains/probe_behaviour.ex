defmodule Marquee.TenantDomains.ProbeBehaviour do
  @moduledoc "Boundary for verified DNS, TLS and application identity readiness."
  @callback check(String.t(), String.t(), map()) :: :ok | {:error, :dns_pending | :tls_pending}
end
