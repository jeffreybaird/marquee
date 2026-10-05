defmodule Marquee.TenantDomains do
  @moduledoc "Backend enrollment, durable provisioning, and exact certificate authorization for managed domains."
  import Ecto.Query
  require Marquee.Otel
  alias Marquee.Accounts
  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.{Events, Metrics, Repo}
  alias Marquee.TenantDomains.{CacheSubscriber, Domain}
  alias Marquee.Workers.TenantDomainProvisioner
  alias MarqueeWeb.OrgURL

  @doc "Returns an organization's allocation, or nil. Requires database access."
  def get_domain(%{id: id}), do: Repo.get_by(Domain, organization_id: id)

  @doc "Enrolls an active organization from a trusted backend caller and durably enqueues provisioning. Requires database access."
  def request_provisioning(%Organization{} = org, opts \\ []) do
    Marquee.Otel.with_span "marquee.tenant_domains.request_provisioning", %{
      "marquee.org.id" => org.id
    } do
      with {:ok, attrs} <- allocation_attrs(org, opts),
           {:ok, domain} <- Repo.transaction(fn -> enroll_locked(org, attrs) end) do
        emit_transition(org, domain)
        {:ok, domain}
      end
    end
  end

  @doc "Checks persisted eligibility and the active organization before allowing a certificate. Requires database access; never contacts providers."
  def allowed_hostname?(hostname) when is_binary(hostname) do
    not is_nil(find_hostname(hostname, [:dns_ready, :ready]))
  end

  def allowed_hostname?(_), do: false

  @doc "Returns a currently eligible managed allocation for a hostname. Requires database access and never contacts providers."
  def find_hostname(hostname, statuses \\ [:ready]) do
    cfg = config()

    if cfg[:enabled] == true and
         cfg[:host_pattern] == Application.get_env(:marquee, :tenant_host_pattern) do
      Repo.one(
        from d in Domain,
          join: org in Organization,
          on: org.id == d.organization_id,
          where: d.hostname == ^hostname and d.status in ^statuses,
          where: d.host_pattern == ^cfg[:host_pattern] and d.dns_zone == ^cfg[:zone],
          where: d.target_ipv4 == ^cfg[:target_ipv4],
          where: not is_nil(d.eligible_at) and not is_nil(d.dns_record_id),
          where: is_nil(org.deleted_at)
      )
    end
  end

  @doc "Resolves a ready managed hostname to its active organization. Requires database access."
  def resolve_hostname(hostname) do
    case find_hostname(hostname) do
      nil -> {:error, :not_found}
      domain -> Accounts.get_organization(domain.organization_id)
    end
  end

  @doc "Returns the ready allocation for a tenant, or nil. Requires database access on cache misses."
  def ready_domain(%{id: id} = org) do
    key = "tenant-domain:#{id}"

    case Marquee.Cache.get(key) do
      {:ok, domain} -> if current_configuration?(domain), do: domain
      :miss -> cache_ready_domain(get_domain(org), key)
    end
  end

  def ready_domain(_), do: nil

  defp cache_ready_domain(%{status: :ready} = domain, key) do
    if current_configuration?(domain) do
      CacheSubscriber.watch(domain.organization_id)
      Marquee.Cache.put(key, domain, ttl: 5_000)
      domain
    end
  end

  defp cache_ready_domain(_, _), do: nil

  defp current_configuration?(domain) do
    cfg = config()

    cfg[:enabled] == true and domain.host_pattern == cfg[:host_pattern] and
      domain.host_pattern == Application.get_env(:marquee, :tenant_host_pattern) and
      domain.dns_zone == cfg[:zone] and domain.target_ipv4 == cfg[:target_ipv4]
  end

  @doc "Returns one bounded keyset page of active organizations before a frozen cutoff. Dry-run only; no enrollment or external calls."
  def migration_snapshot(opts \\ []) do
    cutoff = Keyword.get(opts, :cutoff, DateTime.utc_now() |> DateTime.truncate(:second))
    size = opts |> Keyword.get(:page_size, 100) |> min(100) |> max(1)
    cursor = Keyword.get(opts, :after)
    slugs = Keyword.get(opts, :slugs)

    page =
      Marquee.Admin.tenant_domain_candidates(cutoff, after: cursor, slugs: slugs, per_page: size)

    %{
      cutoff: cutoff,
      cursor: cursor,
      next_cursor: page.next_cursor,
      slugs: slugs,
      host_pattern: config()[:host_pattern],
      organizations: Enum.map(page.results, &snapshot_entry/1)
    }
  end

  @doc "Applies only the IDs and immutable identities in a reviewed snapshot page. Requires database access; only enqueues jobs."
  def apply_snapshot(%{organizations: entries, cutoff: cutoff, host_pattern: pattern})
      when length(entries) <= 100 do
    with true <-
           pattern == config()[:host_pattern] and
             pattern == Application.get_env(:marquee, :tenant_host_pattern),
         {:ok, orgs} <- validate_snapshot(entries, cutoff) do
      Enum.reduce_while(orgs, {:ok, []}, &enroll_snapshot_org/2)
    else
      false -> {:error, :configuration_drift}
      error -> error
    end
  end

  def apply_snapshot(_), do: {:error, :invalid_snapshot}

  defp enroll_snapshot_org(org, {:ok, domains}) do
    case request_provisioning(org, source: :existing_organization) do
      {:ok, domain} -> {:cont, {:ok, [domain | domains]}}
      error -> {:halt, error}
    end
  end

  @doc "Executes one fenced provisioning attempt. Called by the Oban worker; requires database and provider access."
  def provision(organization_id, generation, attempt, max_attempts) do
    Marquee.Otel.with_span "marquee.tenant_domains.provision", %{
      "marquee.org.id" => organization_id
    } do
      case Repo.get_by(Domain, organization_id: organization_id, generation: generation) do
        nil -> :ok
        domain -> provision_current(domain, attempt, max_attempts)
      end
    end
  end

  defp allocation_attrs(org, opts) do
    cfg = config()
    source = Keyword.get(opts, :source)

    cond do
      cfg[:enabled] != true ->
        {:error, :disabled}

      source not in [:backend, :existing_organization] ->
        {:error, :ineligible}

      not is_nil(org.deleted_at) ->
        {:error, :not_found}

      cfg[:host_pattern] != Application.get_env(:marquee, :tenant_host_pattern) ->
        {:error, :configuration_drift}

      true ->
        build_allocation_attrs(org, source, cfg)
    end
  end

  defp build_allocation_attrs(org, source, cfg) do
    with pattern when is_binary(pattern) <- cfg[:host_pattern],
         zone when is_binary(zone) <- cfg[:zone],
         target when is_binary(target) <- cfg[:target_ipv4],
         {:ok, _ip} <- :inet.parse_ipv4_address(String.to_charlist(target)) do
      hostname = OrgURL.tenant_host(%{slug: org.slug}, pattern)

      if String.ends_with?(hostname, "." <> zone) do
        {:ok,
         %{
           hostname: hostname,
           host_pattern: pattern,
           dns_zone: zone,
           target_ipv4: target,
           eligibility_source: source,
           eligible_at: DateTime.utc_now(),
           generation: Ecto.UUID.generate()
         }}
      else
        {:error, :invalid_hostname}
      end
    else
      _ -> {:error, :configuration}
    end
  rescue
    ArgumentError -> {:error, :invalid_hostname}
  end

  defp enroll_locked(org, attrs) do
    active =
      Repo.one(
        from o in Organization,
          where: o.id == ^org.id and is_nil(o.deleted_at),
          lock: "FOR UPDATE"
      )

    if is_nil(active) or active.slug != org.slug, do: Repo.rollback(:not_found)

    domain =
      case get_domain(org) do
        nil -> insert_allocation(org, attrs)
        domain -> validate_existing_allocation(domain, attrs)
      end

    if domain.status != :ready, do: enqueue_provisioning(domain)
    domain
  end

  defp insert_allocation(org, attrs) do
    case %Domain{organization_id: org.id} |> Domain.changeset(attrs) |> Repo.insert() do
      {:ok, domain} -> domain
      {:error, _} -> Repo.rollback(:allocation_conflict)
    end
  end

  defp validate_existing_allocation(domain, attrs) do
    fields = [:hostname, :host_pattern, :dns_zone, :target_ipv4]

    unless Enum.all?(fields, &(Map.fetch!(domain, &1) == Map.fetch!(attrs, &1))),
      do: Repo.rollback(:configuration_drift)

    if domain.status == :failed do
      domain
      |> Ecto.Changeset.change(status: :pending_dns, last_error: nil, ready_at: nil)
      |> Repo.update!()
    else
      domain
    end
  end

  defp enqueue_provisioning(domain) do
    args =
      %{
        organization_id: domain.organization_id,
        generation: domain.generation
      }
      |> Marquee.Otel.put_trace_context()

    case args |> TenantDomainProvisioner.new() |> Oban.insert() do
      {:ok, _} -> :ok
      {:error, _} -> Repo.rollback(:enqueue_failed)
    end
  end

  defp snapshot_entry(org) do
    %{
      organization_id: org.id,
      slug: org.slug,
      inserted_at: org.inserted_at,
      hostname: OrgURL.tenant_host(%{slug: org.slug}, config()[:host_pattern])
    }
  end

  defp validate_snapshot(entries, cutoff) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, orgs} ->
      case Accounts.get_organization(entry.organization_id) do
        {:error, :not_found} -> {:cont, {:ok, orgs}}
        {:ok, org} -> append_snapshot_org(org, entry, cutoff, orgs)
      end
    end)
  end

  defp append_snapshot_org(org, entry, cutoff, orgs) do
    cond do
      not is_nil(org.deleted_at) ->
        {:cont, {:ok, orgs}}

      org.slug == entry.slug and org.inserted_at == entry.inserted_at and
        DateTime.compare(org.inserted_at, cutoff) == :lt and
          snapshot_entry(org).hostname == entry.hostname ->
        {:cont, {:ok, [org | orgs]}}

      true ->
        {:halt, {:error, :snapshot_drift}}
    end
  end

  defp provision_current(domain, attempt, max_attempts) do
    with {:ok, org} <- Accounts.get_organization(domain.organization_id),
         :ok <- validate_active_org(org),
         :ok <- validate_worker_configuration(domain),
         {:ok, claimed} <- claim_lease(domain) do
      try do
        advance_provisioning(org, claimed, attempt, max_attempts)
      after
        release_lease(claimed)
      end
    else
      :ready -> :ok
      {:snooze, _} = busy -> busy
      {:error, reason} -> cancel_domain(domain, reason)
    end
  end

  defp validate_active_org(%{deleted_at: nil}), do: :ok
  defp validate_active_org(_), do: {:error, :not_found}

  defp validate_worker_configuration(domain) do
    cfg = config()

    cond do
      cfg[:enabled] != true ->
        {:error, :disabled}

      cfg[:host_pattern] != domain.host_pattern or
          Application.get_env(:marquee, :tenant_host_pattern) != domain.host_pattern ->
        {:error, :configuration_drift}

      cfg[:zone] != domain.dns_zone or cfg[:target_ipv4] != domain.target_ipv4 ->
        {:error, :configuration_drift}

      domain.status == :ready ->
        :ready

      true ->
        :ok
    end
  end

  defp claim_lease(domain) do
    now = DateTime.utc_now()
    token = Ecto.UUID.generate()

    query =
      from d in Domain,
        where:
          d.id == ^domain.id and d.generation == ^domain.generation and
            (is_nil(d.lease_expires_at) or d.lease_expires_at < ^now),
        select: d

    case Repo.update_all(query,
           set: [lease_token: token, lease_expires_at: DateTime.add(now, 120), updated_at: now]
         ) do
      {1, [%{status: :ready} = claimed]} ->
        release_lease(claimed)
        :ready

      {1, [claimed]} ->
        {:ok, claimed}

      _ ->
        {:snooze, 10}
    end
  end

  defp release_lease(domain),
    do: Repo.update_all(lease_query(domain), set: [lease_token: nil, lease_expires_at: nil])

  defp lease_query(domain) do
    now = DateTime.utc_now()

    from d in Domain,
      where:
        d.id == ^domain.id and d.generation == ^domain.generation and
          d.lease_token == ^domain.lease_token and d.lease_expires_at > ^now
  end

  defp advance_provisioning(org, domain, attempt, max_attempts) do
    case ensure_dns(domain) do
      {:ok, dns_ready} ->
        emit_transition(org, dns_ready)
        verify_readiness(org, dns_ready, attempt, max_attempts)

      {:error, reason} ->
        fail_attempt(org, domain, reason, attempt, max_attempts)
    end
  end

  defp ensure_dns(%{status: :dns_ready} = domain), do: {:ok, domain}

  defp ensure_dns(domain) do
    client =
      Application.get_env(:marquee, :tenant_dns_client, Marquee.TenantDomains.DNSimpleClient)

    key = "tenant-domain:#{domain.id}:#{domain.generation}"

    case bounded_call(
           fn -> client.ensure_record(domain.hostname, domain.target_ipv4, key) end,
           :dns_unavailable
         ) do
      {:ok, %{id: id}} ->
        update_leased(domain, status: :dns_ready, dns_record_id: to_string(id), last_error: nil)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_readiness(org, domain, attempt, max_attempts) do
    probe =
      Application.get_env(:marquee, :tenant_hostname_probe, Marquee.TenantDomains.ReadinessProbe)

    identity = %{domain_id: domain.id, generation: domain.generation}

    case bounded_call(
           fn -> probe.check(domain.hostname, domain.target_ipv4, identity) end,
           :tls_pending
         ) do
      :ok ->
        with {:ok, ready} <-
               update_leased(domain,
                 status: :ready,
                 ready_at: DateTime.utc_now(),
                 last_error: nil
               ) do
          emit_transition(org, ready)
          :ok
        end

      {:error, reason} ->
        fail_attempt(org, domain, reason, attempt, max_attempts)
    end
  end

  defp fail_attempt(org, domain, reason, attempt, max_attempts) do
    permanent? = reason in [:dns_conflict, :configuration, :configuration_drift, :not_found]
    status = if permanent? or attempt >= max_attempts, do: :failed, else: domain.status

    with {:ok, failed} <- update_leased(domain, status: status, last_error: error_code(reason)) do
      emit_transition(org, failed)
      if permanent?, do: {:cancel, reason}, else: {:error, reason}
    end
  end

  defp cancel_domain(domain, reason) do
    query =
      from d in Domain,
        where:
          d.id == ^domain.id and d.generation == ^domain.generation and is_nil(d.lease_token),
        select: d

    result =
      Repo.update_all(query,
        set: [status: :failed, last_error: error_code(reason), updated_at: DateTime.utc_now()]
      )

    with {1, [failed]} <- result,
         {:ok, org} <- Accounts.get_organization(failed.organization_id) do
      emit_transition(org, failed)
    end

    {:cancel, reason}
  end

  defp update_leased(domain, attrs) do
    query = from d in lease_query(domain), select: d

    case Repo.update_all(query, set: Keyword.put(attrs, :updated_at, DateTime.utc_now())) do
      {1, [updated]} -> {:ok, updated}
      _ -> {:error, :stale_lease}
    end
  end

  defp bounded_call(fun, fallback) do
    task =
      Task.async(fn ->
        try do
          fun.()
        rescue
          _ -> {:error, fallback}
        catch
          _, _ -> {:error, fallback}
        end
      end)

    case Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, fallback}
    end
  end

  defp emit_transition(org, domain) do
    Events.broadcast(%Scope{organization: org}, {:tenant_domain_updated, domain})
    Metrics.tenant_domain_transition(org.id, domain.status)
  end

  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_), do: "provider_failure"
  defp config, do: Application.get_env(:marquee, :tenant_domain_provisioning, [])
end
