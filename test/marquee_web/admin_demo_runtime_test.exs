defmodule MarqueeWeb.AdminDemoRuntimeTest do
  use ExUnit.Case, async: false

  @keys ~w(ADMIN_DEMO_ENABLED ADMIN_DEMO_HOST ADMIN_DEMO_TRUSTED_PROXY_IP TENANT_DOMAIN_PROVISIONING ORG_RESOLUTION)

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

  test "runtime defaults disabled and permits preconfigured host while disabled" do
    assert read_config()[:marquee][:admin_demo][:enabled] == false
    System.put_env("ADMIN_DEMO_ENABLED", "false")
    System.put_env("ADMIN_DEMO_HOST", "demo-marquee.example.test")
    config = read_config()[:marquee][:admin_demo]
    assert config[:enabled] == false
    assert config[:host] == "demo-marquee.example.test"
  end

  test "explicit enable binds only the configured host" do
    System.put_env("ADMIN_DEMO_ENABLED", "true")
    System.put_env("ADMIN_DEMO_HOST", "demo-marquee.example.test")
    System.put_env("ADMIN_DEMO_TRUSTED_PROXY_IP", "172.18.0.2")
    config = read_config()[:marquee][:admin_demo]
    assert config[:enabled] == true
    assert config[:host] == "demo-marquee.example.test"
    assert config[:trusted_proxy_ip] == {172, 18, 0, 2}
    assert read_config()[:marquee][MarqueeWeb.Endpoint][:check_origin] == :conn
  end

  test "invalid flag and enabled missing or malformed host fail closed" do
    for {flag, host} <- [
          {"yes", "demo.example.test"},
          {"true", nil},
          {"true", ""},
          {"true", "https://demo.example.test"},
          {"true", "*.example.test"}
        ] do
      System.put_env("ADMIN_DEMO_ENABLED", flag)

      if host,
        do: System.put_env("ADMIN_DEMO_HOST", host),
        else: System.delete_env("ADMIN_DEMO_HOST")

      assert_raise RuntimeError, fn -> read_config() end
    end
  end

  test "deploy and rollback forward opt-in config to both database env variants" do
    for name <- ["deploy", "rollback"] do
      workflow = File.read!(".github/workflows/#{name}.yml")
      assert workflow =~ "ADMIN_DEMO_ENABLED: ${{ vars.ADMIN_DEMO_ENABLED || 'false' }}"
      assert workflow =~ "ADMIN_DEMO_HOST: ${{ vars.ADMIN_DEMO_HOST }}"

      assert length(
               Regex.scan(~r/^\s*ADMIN_DEMO_ENABLED=\$\{ADMIN_DEMO_ENABLED\}\s*$/m, workflow)
             ) == 2

      assert length(Regex.scan(~r/^\s*ADMIN_DEMO_HOST=\$\{ADMIN_DEMO_HOST\}\s*$/m, workflow)) == 2
    end
  end

  test "the staging workflow and its teardown script no longer exist" do
    refute File.exists?(".github/workflows/staging.yml")
    refute File.exists?("deploy/staging-down.sh")
  end

  defp read_config, do: Config.Reader.read!("config/runtime.exs", env: :test)
end
