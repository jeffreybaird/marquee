defmodule MarqueeWeb.TenantProvisioningRuntimeTest do
  use ExUnit.Case, async: false

  @keys ~w(TENANT_DOMAIN_PROVISIONING DNSIMPLE_ACCOUNT_ID DNSIMPLE_API_TOKEN TENANT_DNS_ZONE TENANT_DNS_TARGET_IPV4 TENANT_HOST_PATTERN PHX_HOST ORG_RESOLUTION)

  setup do
    original = Map.new(@keys, &{&1, System.get_env(&1)})
    Enum.each(@keys, &System.delete_env/1)

    on_exit(fn ->
      for {key, value} <- original do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  test "disabled rollout needs no provider credentials and preserves existing defaults" do
    for flag <- [nil, "false"] do
      if flag,
        do: System.put_env("TENANT_DOMAIN_PROVISIONING", flag),
        else: System.delete_env("TENANT_DOMAIN_PROVISIONING")

      config = read_config()
      refute get_in(config, [:marquee, :tenant_domain_provisioning, :enabled])
    end
  end

  test "enabled rollout validates provider config and derives host pattern without requiring hostname global mode" do
    valid_env()
    System.put_env("ORG_RESOLUTION", "query_param")
    config = read_config()
    assert config[:marquee][:org_resolution] == :query_param
    assert config[:marquee][:tenant_host_pattern] == "{slug}-marquee.jeffreybaird.com"
    tenant = config[:marquee][:tenant_domain_provisioning]
    assert tenant[:enabled]
    assert tenant[:zone] == "jeffreybaird.com"
    assert tenant[:account_id] == "123"
    assert tenant[:api_token] == "fixture-secret"
    assert tenant[:target_ipv4] == "192.0.2.25"
    assert tenant[:host_pattern] == config[:marquee][:tenant_host_pattern]
    assert config[:marquee][MarqueeWeb.Endpoint][:check_origin] == :conn
  end

  test "missing credentials invalid IPv4 and mismatched namespace fail before startup without exposing token" do
    for {key, value} <- [
          {"DNSIMPLE_ACCOUNT_ID", nil},
          {"DNSIMPLE_API_TOKEN", nil},
          {"TENANT_DNS_ZONE", nil},
          {"TENANT_DNS_TARGET_IPV4", nil},
          {"TENANT_DNS_TARGET_IPV4", "not-an-ip"},
          {"TENANT_HOST_PATTERN", "{slug}-outside.example"}
        ] do
      valid_env()
      if value, do: System.put_env(key, value), else: System.delete_env(key)
      error = assert_raise RuntimeError, fn -> read_config() end
      refute Exception.message(error) =~ "fixture-secret"
    end
  end

  defp read_config, do: Config.Reader.read!("config/runtime.exs", env: :test)

  defp valid_env do
    System.put_env(%{
      "TENANT_DOMAIN_PROVISIONING" => "true",
      "DNSIMPLE_ACCOUNT_ID" => "123",
      "DNSIMPLE_API_TOKEN" => "fixture-secret",
      "TENANT_DNS_ZONE" => "jeffreybaird.com",
      "TENANT_DNS_TARGET_IPV4" => "192.0.2.25",
      "PHX_HOST" => "marquee.jeffreybaird.com"
    })

    System.delete_env("TENANT_HOST_PATTERN")
  end
end
