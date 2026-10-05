defmodule MarqueeWeb.TenantTLSDeployTest do
  use ExUnit.Case, async: false

  @script Path.expand("../../deploy/tenant-tls.sh", __DIR__)
  @moduletag :tmp_dir

  test "renders strict on-demand namespace plus private blue-green HTTPS-aware authorization relay",
       %{tmp_dir: dir} do
    assert {_output, 0} = run("render", dir)
    global = File.read!(Path.join(dir, "global.options"))
    app = File.read!(Path.join(dir, "marquee.caddy"))
    relay = File.read!(Path.join(dir, "marquee-ask.caddy"))
    assert global =~ "http://127.0.0.1:9080/internal/tenant-domains/ask"
    assert app =~ "on_demand"
    assert app =~ "marquee\\.jeffreybaird\\.com"
    assert relay =~ "127.0.0.1:9080"
    assert relay =~ "marquee-blue:4000"
    assert relay =~ "marquee-green:4000"
    assert relay =~ "X-Forwarded-Proto https"
    refute relay =~ "https://"
  end

  test "refuses another global TLS owner without touching any site", %{tmp_dir: dir} do
    files = baseline(dir, "# marquee-tenant-tls owner=other\nimport /etc/caddy/sites/*.caddy\n")
    assert {_output, status} = run("apply", dir)
    assert status != 0
    assert_snapshot(files)
  end

  test "remote deployment derives the same managed namespace when host pattern is unset or empty",
       %{
         tmp_dir: dir
       } do
    explicit = Path.join(dir, "explicit")
    assert {_output, 0} = run("render", explicit)

    for {label, value} <- [{"unset", nil}, {"empty", ""}] do
      destination = Path.join(dir, label)
      assert {_output, 0} = run("render", destination, [{"TENANT_HOST_PATTERN", value}])

      for file <- ["global.options", "marquee.caddy", "marquee-ask.caddy"] do
        assert File.read!(Path.join(destination, file)) == File.read!(Path.join(explicit, file))
      end
    end
  end

  test "refuses unrecognized global configuration without replacing it", %{tmp_dir: dir} do
    files = baseline(dir, "{\n email owner@example.com\n}\nimport /etc/caddy/sites/*.caddy\n")
    assert {_output, status} = run("apply", dir)
    assert status != 0
    assert_snapshot(files)
  end

  test "validation failure preserves the previous shared proxy and every site", %{tmp_dir: dir} do
    files = baseline(dir)
    bin = fake_tools(dir)

    assert {_output, status} =
             run("apply", dir, [
               {"PATH", bin <> ":" <> System.fetch_env!("PATH")},
               {"FAIL_VALIDATE", "1"}
             ])

    assert status != 0
    assert_snapshot(files)
  end

  test "reload failure restores previous bytes and success preserves unrelated static sites", %{
    tmp_dir: dir
  } do
    files = baseline(dir)
    bin = fake_tools(dir)

    env = [
      {"PATH", bin <> ":" <> System.fetch_env!("PATH")},
      {"RELOAD_MARKER", Path.join(dir, "reload.failed")},
      {"FAIL_RELOAD_ONCE", "1"}
    ]

    assert {_output, status} = run("apply", dir, env)
    assert status != 0
    assert_snapshot(files)
    assert {_output, 0} = run("apply", dir, [{"PATH", bin <> ":" <> System.fetch_env!("PATH")}])

    assert File.read!(Path.join(dir, "sites/other.caddy")) ==
             files[Path.join(dir, "sites/other.caddy")]

    assert File.read!(Path.join(dir, "Caddyfile")) =~ "# marquee-tenant-tls owner=marquee"
  end

  test "malformed namespaces are rejected before rendering", %{tmp_dir: dir} do
    for pattern <- [
          "{slug}.evil.example",
          "{slug}-marquee.jeffreybaird.com\n}",
          "*.jeffreybaird.com",
          "{slug}.{slug}.jeffreybaird.com"
        ] do
      assert {_output, status} = run("render", dir, [{"TENANT_HOST_PATTERN", pattern}])
      assert status != 0
    end
  end

  defp run(action, dir, extra \\ []) do
    env = [
      {"APP_SLUG", "marquee"},
      {"DOMAIN", "marquee.jeffreybaird.com"},
      {"TENANT_HOST_PATTERN", "{slug}-marquee.jeffreybaird.com"},
      {"TENANT_TLS_ON_DEMAND", "true"}
    ]

    System.cmd("bash", [@script, action, dir],
      env: Map.to_list(Map.merge(Map.new(env), Map.new(extra))),
      stderr_to_stdout: true
    )
  end

  defp baseline(dir, caddyfile \\ "import /etc/caddy/sites/*.caddy\n") do
    File.mkdir_p!(Path.join(dir, "sites"))

    files = %{
      Path.join(dir, "Caddyfile") => caddyfile,
      Path.join(dir, "sites/marquee.caddy") => "marquee.jeffreybaird.com {\n respond old\n}\n",
      Path.join(dir, "sites/other.caddy") => "other.example.com {\n respond other-app\n}\n"
    }

    for {path, bytes} <- files, do: File.write!(path, bytes)
    files
  end

  defp assert_snapshot(files),
    do: Enum.each(files, fn {path, bytes} -> assert File.read!(path) == bytes end)

  defp fake_tools(dir) do
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)
    docker = Path.join(bin, "docker")

    File.write!(docker, """
    #!/usr/bin/env bash
    case "$*" in
      *validate*) [ "${FAIL_VALIDATE:-0}" = 1 ] && exit 1 ;;
      *reload*)
        if [ "${FAIL_RELOAD_ONCE:-0}" = 1 ] && [ ! -f "$RELOAD_MARKER" ]; then
          touch "$RELOAD_MARKER"
          exit 1
        fi
        ;;
    esac
    exit 0
    """)

    File.chmod!(docker, 0o755)
    # This harness controls failure recovery; production lock exclusion is
    # reviewed separately. macOS does not ship Linux's flock command.
    flock = Path.join(bin, "flock")
    File.write!(flock, "#!/usr/bin/env bash\nexit 0\n")
    File.chmod!(flock, 0o755)
    bin
  end
end
