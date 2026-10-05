defmodule Marquee.TenantDomainReleaseTest do
  use Marquee.DataCase, async: false
  use Oban.Testing, repo: Marquee.Repo

  import ExUnit.CaptureIO

  alias Marquee.Release
  alias Marquee.TenantDomains
  alias Marquee.TenantDomains.ScriptedClients
  alias Marquee.Workers.TenantDomainProvisioner

  setup do
    pattern = "{slug}-marquee.jeffreybaird.com"

    changes = [
      tenant_domain_provisioning: [
        enabled: true,
        zone: "jeffreybaird.com",
        account_id: "123",
        api_token: "test-token",
        target_ipv4: "192.0.2.25",
        host_pattern: pattern
      ],
      tenant_host_pattern: pattern,
      tenant_dns_client: Marquee.TenantDomains.ScriptedDNSClient,
      tenant_hostname_probe: Marquee.TenantDomains.ScriptedProbe
    ]

    original = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    start_supervised!(ScriptedClients)
    :ok
  end

  @tag :tmp_dir
  test "release dry-run prints an explicit sanitized plan which apply consumes without widening selection",
       %{tmp_dir: tmp_dir} do
    selected = insert(:organization, inserted_at: ~U[2020-01-01 00:00:00Z])
    other = insert(:organization, inserted_at: ~U[2020-01-01 00:00:00Z])

    output =
      capture_io(fn ->
        Release.tenant_domain_snapshot(
          cutoff: ~U[2021-01-01 00:00:00Z],
          slugs: [selected.slug],
          page_size: 2
        )
      end)

    plan = Jason.decode!(String.trim(output))
    assert [%{"organization_id" => id}] = plan["organizations"]
    assert id == selected.id
    refute output =~ "test-token"
    refute output =~ "api_token"
    assert TenantDomains.get_domain(selected) == nil
    assert all_enqueued(worker: TenantDomainProvisioner) == []
    assert ScriptedClients.calls() == []
    path = Path.join(tmp_dir, "tenant-plan.json")
    File.write!(path, output)
    later = insert(:organization, inserted_at: ~U[2020-01-01 00:00:00Z])

    Oban.Testing.with_testing_mode(:manual, fn ->
      capture_io(fn -> assert {:ok, _} = Release.tenant_domain_apply(path) end)
    end)

    assert TenantDomains.get_domain(selected).eligibility_source == :existing_organization
    assert TenantDomains.get_domain(other) == nil
    assert TenantDomains.get_domain(later) == nil
    assert [_job] = all_enqueued(worker: TenantDomainProvisioner)
    assert ScriptedClients.calls() == []
  end

  @tag :tmp_dir
  test "release apply rejects malformed plans without atom creation or enrollment", %{
    tmp_dir: tmp_dir
  } do
    org = insert(:organization)
    path = Path.join(tmp_dir, "invalid-plan.json")
    File.write!(path, Jason.encode!(%{"unexpected_tenant_plan_key_928331" => org.id}))
    capture_io(fn -> assert {:error, _} = Release.tenant_domain_apply(path) end)

    assert_raise ArgumentError, fn ->
      String.to_existing_atom("unexpected_tenant_plan_key_928331")
    end

    File.write!(
      path,
      Jason.encode!(%{
        "cutoff" => nil,
        "host_pattern" => "{slug}-marquee.jeffreybaird.com",
        "organizations" => []
      })
    )

    capture_io(fn ->
      assert {:error, :invalid_snapshot} = Release.tenant_domain_apply(path)
    end)

    assert TenantDomains.get_domain(org) == nil
    assert all_enqueued(worker: TenantDomainProvisioner) == []
    assert ScriptedClients.calls() == []
  end
end
