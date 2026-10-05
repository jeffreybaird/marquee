defmodule MarqueeWeb.AdminDemoProxyDeployTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir
  @script Path.expand("../../deploy/admin-demo-proxy.sh", __DIR__)

  setup %{tmp_dir: dir} do
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)
    docker = Path.join(bin, "docker")

    File.write!(docker, """
    #!/bin/sh
    case "$*" in
      'compose -f /root/caddy/compose.yaml ps -q caddy') printf '%s\\n' 'caddy-container' ;;
      inspect*) printf '%s\\n' "$TEST_EDGE_IP" ;;
      *) exit 91 ;;
    esac
    """)

    File.chmod!(docker, 0o755)
    path = Path.join(dir, ".env")

    File.write!(
      path,
      "DOMAIN=marquee.example.test\nADMIN_DEMO_TRUSTED_PROXY_IP=192.0.2.1\nKEEP_EXISTING=yes\n"
    )

    %{dir: dir, env_path: path, bin: bin}
  end

  test "host helper discovers current Caddy edge address and replaces stale value without changing other settings",
       ctx do
    assert {_, 0} = run_helper(ctx, "172.18.0.2")
    result = File.read!(ctx.env_path)
    assert result =~ "ADMIN_DEMO_TRUSTED_PROXY_IP=172.18.0.2"
    assert result =~ "DOMAIN=marquee.example.test"
    assert result =~ "KEEP_EXISTING=yes"
    assert length(Regex.scan(~r/^ADMIN_DEMO_TRUSTED_PROXY_IP=/m, result)) == 1
    assert {_, 0} = run_helper(ctx, "172.18.0.3")
    assert File.read!(ctx.env_path) =~ "ADMIN_DEMO_TRUSTED_PROXY_IP=172.18.0.3"

    for name <- ["deploy", "rollback"] do
      workflow = File.read!(".github/workflows/#{name}.yml")
      assert workflow =~ "admin-demo-proxy.sh"
      refute workflow =~ "vars.ADMIN_DEMO_TRUSTED_PROXY_IP"
    end
  end

  test "missing or malformed discovered address leaves existing deployment env intact", ctx do
    original = File.read!(ctx.env_path)

    for address <- ["", "not-an-ip", "172.18.0.2\nEVIL=yes", "172.18.0.2,192.0.2.3"] do
      assert {_, status} = run_helper(ctx, address)
      assert status != 0
      assert File.read!(ctx.env_path) == original
    end
  end

  defp run_helper(ctx, ip) do
    System.cmd("bash", [@script, ctx.dir],
      stderr_to_stdout: true,
      env: [{"PATH", ctx.bin <> ":" <> System.get_env("PATH", "")}, {"TEST_EDGE_IP", ip}]
    )
  end
end
