defmodule Marquee.TenantDomainsTest do
  use Marquee.DataCase, async: false
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.TenantDomains
  alias Marquee.TenantDomains.ScriptedClients
  alias Marquee.Workers.TenantDomainProvisioner

  @pattern "{slug}-marquee.jeffreybaird.com"
  @target "192.0.2.25"

  setup do
    config = [
      enabled: true,
      zone: "jeffreybaird.com",
      account_id: "123",
      api_token: "test-token",
      target_ipv4: @target,
      host_pattern: @pattern
    ]

    changes = [
      tenant_domain_provisioning: config,
      tenant_host_pattern: @pattern,
      tenant_dns_client: Marquee.TenantDomains.ScriptedDNSClient,
      tenant_hostname_probe: Marquee.TenantDomains.ScriptedProbe
    ]

    originals = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- originals do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    start_supervised!(ScriptedClients)
    :ok
  end

  test "backend enrollment freezes identity, records eligibility and enqueues one unique job" do
    org = insert(:organization)
    assert TenantDomains.get_domain(org) == nil
    assert {:ok, domain} = enroll(org)
    assert domain.organization_id == org.id
    assert domain.hostname == "#{org.slug}-marquee.jeffreybaird.com"
    assert domain.status == :pending_dns
    assert domain.eligibility_source == :backend
    assert domain.eligible_at != nil
    assert domain.generation != nil
    assert domain.ready_at == nil
    assert {:ok, same} = enroll(org)
    assert same.id == domain.id
    assert same.generation == domain.generation
    assert [%{args: args}] = all_enqueued(worker: TenantDomainProvisioner)
    assert args["organization_id"] == org.id
    assert args["generation"] == domain.generation
    assert ScriptedClients.calls() == []
  end

  test "organization creation does not enroll and deleted organizations cannot enroll" do
    active = insert(:organization)
    deleted = insert(:organization, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    assert TenantDomains.get_domain(active) == nil
    assert {:error, _} = enroll(deleted)
    assert TenantDomains.get_domain(deleted) == nil
    assert all_enqueued(worker: TenantDomainProvisioner) == []
    assert ScriptedClients.calls() == []
  end

  test "worker creates DNS then verifies the same application identity before ready" do
    org = insert(:organization)
    {:ok, domain} = enroll(org)
    ScriptedClients.script(:dns, [{:ok, %{id: "record-1"}}])
    ScriptedClients.script(:probe, [:ok])
    assert :ok = run(domain)
    ready = TenantDomains.get_domain(org)
    assert ready.status == :ready
    assert ready.dns_record_id == "record-1"
    assert ready.ready_at != nil

    assert [{:dns, [host, @target, key]}, {:probe, [host, @target, identity]}] =
             ScriptedClients.calls()

    assert host == domain.hostname
    assert is_binary(key) and key != ""
    assert identity == %{domain_id: domain.id, generation: domain.generation}
    assert TenantDomains.allowed_hostname?(host)
    assert :ok = run(domain)
    assert length(ScriptedClients.calls()) == 2
  end

  test "TLS pending remains DNS-ready, permits issuance, retries without DNS mutation" do
    org = insert(:organization)
    {:ok, domain} = enroll(org)
    ScriptedClients.script(:dns, [{:ok, %{id: "record-1"}}])
    ScriptedClients.script(:probe, [{:error, :tls_pending}, :ok])
    assert {:error, :tls_pending} = run(domain)
    pending = TenantDomains.get_domain(org)
    assert pending.status == :dns_ready
    assert pending.ready_at == nil
    assert pending.last_error != nil
    assert TenantDomains.allowed_hostname?(pending.hostname)
    assert :ok = run(domain)
    assert TenantDomains.get_domain(org).status == :ready
    assert Enum.count(ScriptedClients.calls(), &(elem(&1, 0) == :dns)) == 1
  end

  test "DNS transient failure retries pending, while conflict fails closed without probe" do
    org = insert(:organization)
    {:ok, domain} = enroll(org)
    ScriptedClients.script(:dns, [{:error, :dns_unavailable}, {:error, :dns_conflict}])
    assert {:error, :dns_unavailable} = run(domain)
    assert TenantDomains.get_domain(org).status == :pending_dns
    refute TenantDomains.allowed_hostname?(domain.hostname)
    assert {:cancel, :dns_conflict} = run(domain)
    failed = TenantDomains.get_domain(org)
    assert failed.status == :failed
    assert failed.ready_at == nil
    refute TenantDomains.allowed_hostname?(domain.hostname)
    assert Enum.all?(ScriptedClients.calls(), &(elem(&1, 0) == :dns))
    assert {:ok, retry} = enroll(org)
    assert retry.id == domain.id
    assert retry.generation == domain.generation
    assert retry.status == :pending_dns
  end

  test "stale jobs, deleted orgs and changed hostname configuration cannot provision" do
    org = insert(:organization)
    {:ok, domain} = enroll(org)
    assert :ok = run(%{domain | generation: Ecto.UUID.generate()})
    assert ScriptedClients.calls() == []
    Application.put_env(:marquee, :tenant_host_pattern, "{slug}-different.jeffreybaird.com")
    assert {:cancel, _} = run(domain)
    assert TenantDomains.get_domain(org).status == :failed
    assert ScriptedClients.calls() == []
    Application.put_env(:marquee, :tenant_host_pattern, @pattern)

    Repo.update!(
      Ecto.Changeset.change(org, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    )

    assert {:cancel, _} = run(domain)
    refute TenantDomains.allowed_hostname?(domain.hostname)
  end

  test "certificate authorization is exact, persisted, eligible and active with no provider calls" do
    org = insert(:organization)
    {:ok, domain} = enroll(org)
    refute TenantDomains.allowed_hostname?(domain.hostname)
    domain = Repo.update!(Ecto.Changeset.change(domain, status: :dns_ready, dns_record_id: "123"))
    assert TenantDomains.allowed_hostname?(domain.hostname)

    for host <- [
          "missing-marquee.jeffreybaird.com",
          "marquee.jeffreybaird.com",
          "#{domain.hostname}.evil.com",
          "nested.#{domain.hostname}",
          "watch.example.com",
          String.upcase(domain.hostname)
        ] do
      refute TenantDomains.allowed_hostname?(host), host
    end

    Repo.update!(
      Ecto.Changeset.change(org, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    )

    refute TenantDomains.allowed_hostname?(domain.hostname)
    assert ScriptedClients.calls() == []
  end

  test "overlapping worker executions allow only one lease owner to call DNS" do
    org = insert(:organization)
    {:ok, domain} = enroll(org)
    owner = self()

    ScriptedClients.script(:dns, [
      fn _args ->
        send(owner, {:dns_entered, self()})

        receive do
          :release_dns -> {:ok, %{id: "record-1"}}
        after
          5_000 -> {:error, :dns_unavailable}
        end
      end
    ])

    ScriptedClients.script(:probe, [:ok])
    task = Task.async(fn -> run(domain) end)
    assert_receive {:dns_entered, worker}, 2_000
    assert {:snooze, seconds} = run(domain)
    assert seconds > 0
    send(worker, :release_dns)
    assert :ok = Task.await(task)
    assert TenantDomains.get_domain(org).status == :ready
    assert Enum.count(ScriptedClients.calls(), &(elem(&1, 0) == :dns)) == 1
  end

  test "migration slug allowlist is explicit and does not enroll unselected active organizations" do
    selected = insert(:organization, inserted_at: ~U[2020-01-01 00:00:00Z])
    other = insert(:organization, inserted_at: ~U[2020-01-01 00:00:00Z])

    page =
      TenantDomains.migration_snapshot(
        cutoff: ~U[2021-01-01 00:00:00Z],
        slugs: [selected.slug],
        page_size: 2
      )

    assert [%{organization_id: id}] = page.organizations
    assert id == selected.id

    assert {:ok, _} =
             Oban.Testing.with_testing_mode(:manual, fn -> TenantDomains.apply_snapshot(page) end)

    assert TenantDomains.get_domain(selected).eligibility_source == :existing_organization
    assert TenantDomains.get_domain(other) == nil
  end

  test "disabled provisioning rejects enrollment and issuance and never calls providers" do
    org = insert(:organization)
    {:ok, domain} = enroll(org)
    config = Application.fetch_env!(:marquee, :tenant_domain_provisioning)

    Application.put_env(
      :marquee,
      :tenant_domain_provisioning,
      Keyword.put(config, :enabled, false)
    )

    assert {:error, _} = enroll(insert(:organization))
    refute TenantDomains.allowed_hostname?(domain.hostname)
    assert {:cancel, _} = run(domain)
    assert ScriptedClients.calls() == []
  end

  test "certificate authorization fails closed immediately when frozen provisioning configuration drifts" do
    org = insert(:organization)
    {:ok, domain} = enroll(org)
    domain = Repo.update!(Ecto.Changeset.change(domain, status: :dns_ready, dns_record_id: "123"))
    config = Application.fetch_env!(:marquee, :tenant_domain_provisioning)
    assert TenantDomains.allowed_hostname?(domain.hostname)
    Application.put_env(:marquee, :tenant_host_pattern, "{slug}-other.jeffreybaird.com")
    refute TenantDomains.allowed_hostname?(domain.hostname)
    Application.put_env(:marquee, :tenant_host_pattern, @pattern)

    for {key, value} <- [
          zone: "other.example",
          target_ipv4: "192.0.2.99",
          host_pattern: "{slug}-other.jeffreybaird.com"
        ] do
      Application.put_env(:marquee, :tenant_domain_provisioning, Keyword.put(config, key, value))
      refute TenantDomains.allowed_hostname?(domain.hostname)
      Application.put_env(:marquee, :tenant_domain_provisioning, config)
    end

    assert ScriptedClients.calls() == []
  end

  test "snapshot apply rejects changed tenant identity and changed namespace without enrollment" do
    org = insert(:organization, inserted_at: ~U[2020-01-01 00:00:00Z])
    page = TenantDomains.migration_snapshot(cutoff: ~U[2021-01-01 00:00:00Z], page_size: 2)
    updated = Repo.update!(Ecto.Changeset.change(org, slug: "renamed-studio"))

    assert {:error, _} =
             Oban.Testing.with_testing_mode(:manual, fn -> TenantDomains.apply_snapshot(page) end)

    assert TenantDomains.get_domain(updated) == nil
    Repo.update!(Ecto.Changeset.change(updated, slug: org.slug))
    Application.put_env(:marquee, :tenant_host_pattern, "{slug}-different.jeffreybaird.com")

    assert {:error, _} =
             Oban.Testing.with_testing_mode(:manual, fn -> TenantDomains.apply_snapshot(page) end)

    assert TenantDomains.get_domain(org) == nil
    assert ScriptedClients.calls() == []
  end

  test "migration dry-run pages a frozen active snapshot without writes and apply enrolls only listed IDs" do
    old = ~U[2020-01-01 00:00:00Z]
    orgs = for _ <- 1..5, do: insert(:organization, inserted_at: old)
    deleted = insert(:organization, inserted_at: old, deleted_at: ~U[2020-01-02 00:00:00Z])
    cutoff = ~U[2021-01-01 00:00:00Z]
    later = insert(:organization, inserted_at: ~U[2022-01-01 00:00:00Z])
    first = TenantDomains.migration_snapshot(cutoff: cutoff, page_size: 2)
    assert length(first.organizations) == 2

    second =
      TenantDomains.migration_snapshot(
        cutoff: first.cutoff,
        after: first.next_cursor,
        page_size: 2
      )

    third =
      TenantDomains.migration_snapshot(
        cutoff: first.cutoff,
        after: second.next_cursor,
        page_size: 2
      )

    assert third.next_cursor == nil
    selected = first.organizations ++ second.organizations ++ third.organizations

    assert Enum.sort(Enum.map(selected, & &1.organization_id)) ==
             Enum.sort(Enum.map(orgs, & &1.id))

    assert Enum.all?(
             selected,
             &(Map.keys(&1)
               |> Enum.all?(fn key ->
                 key in [:organization_id, :slug, :hostname, :inserted_at]
               end))
           )

    assert Enum.all?(orgs, &(TenantDomains.get_domain(&1) == nil))
    assert all_enqueued(worker: TenantDomainProvisioner) == []
    assert ScriptedClients.calls() == []

    for page <- [first, second, third] do
      assert {:ok, _} =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 TenantDomains.apply_snapshot(page)
               end)
    end

    assert Enum.all?(
             orgs,
             &(TenantDomains.get_domain(&1).eligibility_source == :existing_organization)
           )

    assert TenantDomains.get_domain(deleted) == nil
    assert TenantDomains.get_domain(later) == nil
    assert length(all_enqueued(worker: TenantDomainProvisioner)) == 5
  end

  defp enroll(org),
    do:
      Oban.Testing.with_testing_mode(:manual, fn ->
        TenantDomains.request_provisioning(org, source: :backend)
      end)

  defp run(domain),
    do:
      perform_job(TenantDomainProvisioner, %{
        "organization_id" => domain.organization_id,
        "generation" => domain.generation
      })
end
