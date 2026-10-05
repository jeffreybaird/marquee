defmodule Marquee.Workers.TenantDomainProvisioner do
  @moduledoc "Retries managed DNS and TLS provisioning under a persisted fencing lease."
  use Oban.Worker,
    queue: :tenant_domains,
    max_attempts: 12,
    unique: [
      period: :infinity,
      fields: [:args],
      keys: [:organization_id, :generation],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def perform(
        %Oban.Job{args: %{"organization_id" => org_id, "generation" => generation} = args} = job
      ) do
    Marquee.Otel.extract_trace_context(args["trace_context"])
    Logger.metadata(org_id: org_id, worker: "TenantDomainProvisioner")
    Tracer.set_attributes([{"marquee.org.id", org_id}, {"oban.attempt", job.attempt}])
    Marquee.TenantDomains.provision(org_id, generation, job.attempt, job.max_attempts)
  end
end
