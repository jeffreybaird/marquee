defmodule Marquee.AdminDemoReleaseTest do
  use Marquee.DataCase, async: false
  use Oban.Testing, repo: Marquee.Repo
  import ExUnit.CaptureIO

  alias Marquee.{AdminDemo, Release, TenantDomains}
  alias Marquee.Workers.TenantDomainProvisioner

  @moduletag :tmp_dir
  @host "demo-marquee.example.test"

  setup %{tmp_dir: dir} do
    path = Path.join(dir, "travel.json")
    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))
    pattern = "{slug}-marquee.example.test"

    changes = [
      admin_demo: [enabled: false, host: @host, catalog_path: path],
      tenant_host_pattern: pattern,
      tenant_domain_provisioning: [
        enabled: true,
        zone: "example.test",
        account_id: "123",
        api_token: "test-private-token",
        target_ipv4: "192.0.2.25",
        host_pattern: pattern
      ]
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

    :ok
  end

  test "disabled release bootstrap enrolls only exact service host idempotently and prints no credentials" do
    output =
      Oban.Testing.with_testing_mode(:manual, fn ->
        capture_io(fn ->
          assert {:ok, %{organization: org, domain: domain}} = Release.configure_admin_demo_host()
          assert org.demo_kind == :admin_demo_host
          assert domain.hostname == @host

          assert {:ok, %{organization: repeated, domain: again}} =
                   Release.configure_admin_demo_host()

          assert repeated.id == org.id
          assert again.id == domain.id

          assert {:error, :demo_forbidden} =
                   TenantDomains.request_provisioning(org, source: :backend)
        end)
      end)

    assert length(all_enqueued(worker: TenantDomainProvisioner)) == 1
    refute output =~ "test-private-token"
    refute output =~ "@"
    assert {:error, :disabled} = AdminDemo.start_session()
  end

  test "public entry URL requires both enabled feature and ready configured service hostname" do
    assert AdminDemo.entry_url() == nil

    {:ok, %{organization: org, domain: domain}} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Release.configure_admin_demo_host()
      end)

    config = Application.fetch_env!(:marquee, :admin_demo)
    Application.put_env(:marquee, :admin_demo, Keyword.put(config, :enabled, true))
    assert AdminDemo.entry_url() == nil

    Repo.update!(
      Ecto.Changeset.change(domain,
        status: :ready,
        dns_record_id: "fixture-record",
        ready_at: DateTime.utc_now()
      )
    )

    assert AdminDemo.entry_url() == "https://#{@host}/demo/admin"
    Application.put_env(:marquee, :admin_demo, config)
    assert AdminDemo.entry_url() == nil
    assert TenantDomains.get_domain(org).status == :ready
  end
end
