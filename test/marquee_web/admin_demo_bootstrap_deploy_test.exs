defmodule MarqueeWeb.AdminDemoBootstrapDeployTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir
  @script Path.expand("../../deploy/admin-demo-bootstrap.sh", __DIR__)

  setup %{tmp_dir: dir} do
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)
    docker = Path.join(bin, "docker")

    File.write!(
      docker,
      "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$TEST_DOCKER_LOG\"\nexit \"${TEST_DOCKER_STATUS:-0}\"\n"
    )

    File.chmod!(docker, 0o755)
    File.write!(Path.join(dir, ".env"), "ADMIN_DEMO_ENABLED=false\n")
    %{dir: dir, bin: bin, log: Path.join(dir, "docker.log")}
  end

  test "configured host bootstraps the new release with feature disabled and empty host skips",
       ctx do
    assert {_, 0} = run_helper(ctx, "")
    refute File.exists?(ctx.log)
    assert {_, 0} = run_helper(ctx, "demo-marquee.example.test")
    command = File.read!(ctx.log)

    assert command =~ "compose run --rm -e POOL_SIZE=2 migrate bin/marquee eval"
    assert command =~ "case Marquee.Release.configure_admin_demo_host() do"
    assert command =~ "{:ok, _} -> :ok"
    assert command =~ "System.halt(1)"

    refute command =~ "rpc"
    assert File.read!(Path.join(ctx.dir, ".env")) == "ADMIN_DEMO_ENABLED=false\n"
    workflow = File.read!(".github/workflows/deploy.yml")
    swap = :binary.matches(workflow, "bash '$STACK_DIR'/swap.sh") |> List.last() |> elem(0)

    bootstrap =
      :binary.matches(workflow, "bash '$STACK_DIR'/admin-demo-bootstrap.sh")
      |> List.last()
      |> elem(0)

    assert bootstrap > swap
    assert workflow =~ "deploy/admin-demo-bootstrap.sh"
  end

  test "bootstrap failure propagates without trying to restart or roll back old workers", ctx do
    assert {_, status} = run_helper(ctx, "demo-marquee.example.test", "42")
    assert status != 0
    commands = File.read!(ctx.log) |> String.split("\n", trim: true)
    assert length(commands) == 1
    refute hd(commands) =~ " start "
    refute hd(commands) =~ " up "
    assert File.read!(Path.join(ctx.dir, ".env")) == "ADMIN_DEMO_ENABLED=false\n"
  end

  defp run_helper(ctx, host, status \\ "0") do
    System.cmd("bash", [@script, ctx.dir, "marquee", "Marquee", host],
      stderr_to_stdout: true,
      env: [
        {"PATH", ctx.bin <> ":" <> System.get_env("PATH", "")},
        {"TEST_DOCKER_LOG", ctx.log},
        {"TEST_DOCKER_STATUS", status}
      ]
    )
  end
end
