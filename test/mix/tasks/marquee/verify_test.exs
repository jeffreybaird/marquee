defmodule Mix.Tasks.Marquee.VerifyTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Marquee.Verify

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

  describe "steps/1" do
    test "runs the fast checks before the slow ones and the browser suite last" do
      names = Verify.steps([]) |> Enum.map(&elem(&1, 0))

      assert List.first(names) == :format
      assert List.last(names) == :e2e

      assert Enum.find_index(names, &(&1 == :assets_typecheck)) <
               Enum.find_index(names, &(&1 == :test))

      assert Enum.find_index(names, &(&1 == :test)) < Enum.find_index(names, &(&1 == :dialyzer))
    end

    test "matches what CI runs" do
      commands = Verify.steps([]) |> Enum.map(&elem(&1, 1))

      assert {"mix", ["format", "--check-formatted"]} in commands
      assert {"mix", ["compile", "--force", "--warnings-as-errors"]} in commands
      assert {"mix", ["credo", "--strict"]} in commands
      assert {"npm", ["run", "typecheck", "--prefix", "assets"]} in commands
      assert {"npm", ["test", "--prefix", "assets"]} in commands
      assert {"mix", ["test"]} in commands
    end

    test "--no-e2e and --no-dialyzer drop only their step" do
      assert :e2e not in step_names(e2e: false)
      assert :dialyzer in step_names(e2e: false)
      assert :dialyzer not in step_names(dialyzer: false)
      assert length(step_names(dialyzer: false, e2e: false)) == length(step_names([])) - 2
    end

    test "audits dependencies right after credo and before the asset checks" do
      names = step_names([])
      credo_index = Enum.find_index(names, &(&1 == :credo))

      assert Enum.at(names, credo_index + 1) == :deps_audit
      assert Enum.at(names, credo_index + 2) == :assets_typecheck

      assert names == [
               :format,
               :compile,
               :credo,
               :deps_audit,
               :assets_typecheck,
               :assets_test,
               :assets_build,
               :test,
               :dialyzer,
               :e2e
             ]
    end

    test "runs the dependency audit as mix deps.audit" do
      commands = Verify.steps([]) |> Enum.map(&elem(&1, 1))

      assert {"mix", ["deps.audit"]} in commands

      assert List.keyfind(Verify.steps([]), :deps_audit, 0) ==
               {:deps_audit, {"mix", ["deps.audit"]}}
    end

    test "--no-deps-audit drops only the dependency audit" do
      names = step_names(deps_audit: false)

      assert :deps_audit not in names
      assert names == List.delete(step_names([]), :deps_audit)
      assert length(names) == length(step_names([])) - 1
    end

    test "--no-e2e and --no-dialyzer keep the dependency audit" do
      assert :deps_audit in step_names(e2e: false, dialyzer: false)
      assert :deps_audit in step_names(e2e: false)
      assert :deps_audit in step_names(dialyzer: false)
    end
  end

  describe "run_steps/2" do
    test "runs every step in order when all succeed" do
      {:ok, log} = Agent.start_link(fn -> [] end)

      assert :ok =
               Verify.run_steps(Verify.steps([]), fn command ->
                 Agent.update(log, &[command | &1])
                 0
               end)

      assert Agent.get(log, &Enum.reverse/1) == Enum.map(Verify.steps([]), &elem(&1, 1))

      assert_received {:mix_shell, :info,
                       ["==> marquee.verify: format (mix format --check-formatted)"]}

      assert_received {:mix_shell, :info, ["==> marquee.verify: deps_audit (mix deps.audit)"]}

      assert_received {:mix_shell, :info, ["==> marquee.verify: e2e (mix test --only e2e)"]}
    end

    test "stops at the first failure and reports the step" do
      {:ok, log} = Agent.start_link(fn -> [] end)

      runner = fn
        {"mix", ["credo" | _]} = command ->
          Agent.update(log, &[command | &1])
          2

        command ->
          Agent.update(log, &[command | &1])
          0
      end

      assert_raise Mix.Error, ~r/credo failed with exit status 2/, fn ->
        Verify.run_steps(Verify.steps([]), runner)
      end

      assert Agent.get(log, &Enum.reverse/1) == [
               {"mix", ["format", "--check-formatted"]},
               {"mix", ["compile", "--force", "--warnings-as-errors"]},
               {"mix", ["credo", "--strict"]}
             ]
    end
  end

  defp step_names(opts), do: Verify.steps(opts) |> Enum.map(&elem(&1, 0))
end
