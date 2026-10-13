defmodule MarqueeWeb.DemoContentBootstrapDeployTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir
  @script Path.expand("../../deploy/demo-content-bootstrap.sh", __DIR__)

  setup %{tmp_dir: dir} do
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)

    File.write!(
      Path.join(bin, "docker"),
      "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$TEST_DOCKER_LOG\"\nexit \"${TEST_DOCKER_STATUS:-0}\"\n"
    )

    File.chmod!(Path.join(bin, "docker"), 0o755)
    File.write!(Path.join(dir, ".env"), "EXISTING_ENV=preserved\n")
    %{dir: dir, bin: bin, log: Path.join(dir, "docker.log")}
  end

  test "bootstrap uses gated offline release eval before traffic swap and is delivered to stack",
       ctx do
    assert {_, 0} = run_helper(ctx, "0")
    command = File.read!(ctx.log)
    assert command =~ "compose run --rm -e POOL_SIZE=2 migrate bin/marquee eval"
    assert command =~ "case Marquee.Release.seed_missing_demo_content() do"
    assert command =~ "{:ok, _} -> :ok"
    assert command =~ "System.halt(1)"
    refute command =~ "rpc"
    refute command =~ "mix "
    assert File.read!(Path.join(ctx.dir, ".env")) == "EXISTING_ENV=preserved\n"
    workflow = File.read!(".github/workflows/deploy.yml")
    assert workflow =~ "deploy/demo-content-bootstrap.sh"

    transfer_lines =
      workflow
      |> String.split("\n")
      |> Enum.filter(
        &(String.contains?(&1, "deploy/compose.yaml") and String.contains?(&1, "deploy/swap.sh"))
      )

    assert length(transfer_lines) == 2
    assert Enum.all?(transfer_lines, &String.contains?(&1, "deploy/demo-content-bootstrap.sh"))

    bootstrap =
      workflow
      |> :binary.matches("bash '$STACK_DIR'/demo-content-bootstrap.sh")
      |> List.last()
      |> elem(0)

    swap = workflow |> :binary.matches("bash '$STACK_DIR'/swap.sh") |> List.last() |> elem(0)
    migrate = workflow |> :binary.matches(".Release.migrate()") |> List.last() |> elem(0)
    assert migrate < bootstrap
    assert bootstrap < swap
  end

  test "seed failure propagates and does not attempt a traffic swap", ctx do
    assert {_, status} = run_helper(ctx, "42")
    assert status != 0
    assert [_] = File.read!(ctx.log) |> String.split("\n", trim: true)
    refute File.read!(ctx.log) =~ " up "
    refute File.read!(ctx.log) =~ " start "
    assert File.read!(Path.join(ctx.dir, ".env")) == "EXISTING_ENV=preserved\n"
  end

  defp run_helper(ctx, status) do
    System.cmd("bash", [@script, ctx.dir, "marquee", "Marquee"],
      stderr_to_stdout: true,
      env: [
        {"PATH", ctx.bin <> ":" <> System.get_env("PATH", "")},
        {"TEST_DOCKER_LOG", ctx.log},
        {"TEST_DOCKER_STATUS", status}
      ]
    )
  end
end
