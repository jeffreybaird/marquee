defmodule Mix.Tasks.Marquee.Verify do
  @shortdoc "Runs every local check CI runs, fastest first; stops at the first failure"

  @moduledoc """
  Runs the full verification suite, in this order:

  1. `mix format --check-formatted`
  2. `mix compile --force --warnings-as-errors`
  3. `mix credo --strict`
  4. `npm run typecheck --prefix assets` (`tsc --noEmit`)
  5. `npm test --prefix assets` (vitest)
  6. `mix esbuild marquee`
  7. `mix test` (unit and integration, e2e excluded)
  8. `mix dialyzer`
  9. `mix test --only e2e` (needs Chrome and ChromeDriver)

  Each step runs as its own `mix` or `npm` process so it behaves exactly as it
  does on the command line and in CI. The suite stops at the first failing
  step and exits non-zero.

  ## Usage

      mix marquee.verify
      mix marquee.verify --no-e2e
      mix marquee.verify --no-dialyzer --no-e2e

  ## Options

    * `--no-e2e` - skip the Wallaby browser suite
    * `--no-dialyzer` - skip dialyzer (slow until its PLT is built)
  """

  use Mix.Task

  @type step_name ::
          :format
          | :compile
          | :credo
          | :assets_typecheck
          | :assets_test
          | :assets_build
          | :test
          | :dialyzer
          | :e2e
  @type command :: {String.t(), [String.t()]}
  @type step :: {step_name(), command()}
  @type runner :: (command() -> non_neg_integer())

  @switches [e2e: :boolean, dialyzer: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _positional, _invalid} = OptionParser.parse(args, switches: @switches)

    opts
    |> steps()
    |> run_steps(&run_command/1)
  end

  @doc """
  Returns the ordered steps for the given options as `{name, {executable, args}}`.

      iex> Mix.Tasks.Marquee.Verify.steps([]) |> Enum.map(&elem(&1, 0))
      [:format, :compile, :credo, :assets_typecheck, :assets_test, :assets_build, :test, :dialyzer, :e2e]

      iex> Mix.Tasks.Marquee.Verify.steps(e2e: false, dialyzer: false) |> Enum.map(&elem(&1, 0))
      [:format, :compile, :credo, :assets_typecheck, :assets_test, :assets_build, :test]

      iex> Mix.Tasks.Marquee.Verify.steps([]) |> List.keyfind(:e2e, 0)
      {:e2e, {"mix", ["test", "--only", "e2e"]}}
  """
  @spec steps(keyword()) :: [step()]
  def steps(opts) do
    [
      {:format, {"mix", ["format", "--check-formatted"]}},
      {:compile, {"mix", ["compile", "--force", "--warnings-as-errors"]}},
      {:credo, {"mix", ["credo", "--strict"]}},
      {:assets_typecheck, {"npm", ["run", "typecheck", "--prefix", "assets"]}},
      {:assets_test, {"npm", ["test", "--prefix", "assets"]}},
      {:assets_build, {"mix", ["esbuild", "marquee"]}},
      {:test, {"mix", ["test"]}},
      {:dialyzer, {"mix", ["dialyzer"]}},
      {:e2e, {"mix", ["test", "--only", "e2e"]}}
    ]
    |> reject_disabled_steps(opts)
  end

  @doc """
  Runs `steps` in order through `runner`, which executes a command and returns
  its exit status. Stops at the first non-zero status by raising `Mix.Error`,
  so the process exits non-zero and later steps never run.

      iex> Mix.Tasks.Marquee.Verify.run_steps([{:format, {"true", []}}], fn _ -> 0 end)
      :ok
  """
  @spec run_steps([step()], runner()) :: :ok
  def run_steps(steps, runner) do
    Enum.each(steps, fn {name, command} ->
      Mix.shell().info("==> marquee.verify: #{name} (#{render_command(command)})")

      case runner.(command) do
        0 -> :ok
        status -> Mix.raise("marquee.verify: #{name} failed with exit status #{status}")
      end
    end)
  end

  defp reject_disabled_steps(steps, opts) do
    Enum.reject(steps, fn {name, _command} ->
      Keyword.get(opts, name, true) == false
    end)
  end

  defp run_command({executable, args}) do
    case System.find_executable(executable) do
      nil ->
        Mix.shell().error("marquee.verify: `#{executable}` not found on PATH")
        127

      path ->
        {_output, status} =
          System.cmd(path, args,
            into: IO.stream(),
            stderr_to_stdout: true,
            env: [{"MIX_ENV", "test"}]
          )

        status
    end
  end

  defp render_command({executable, args}), do: Enum.join([executable | args], " ")
end
