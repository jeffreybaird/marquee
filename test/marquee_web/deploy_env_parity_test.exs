defmodule MarqueeWeb.DeployEnvParityTest do
  @moduledoc """
  The rollback workflow must write the same `.env` contract as the deploy
  workflow (only the IMAGE value differs), and both must ship the
  DigitalOcean Spaces settings to production.
  """
  use ExUnit.Case, async: true

  @variants %{
    postgres: {"Write .env (Postgres)", "Write .env (Postgres, pinned image)"},
    sqlite: {"Write .env (SQLite)", "Write .env (SQLite, pinned image)"}
  }

  @spaces_lines [
    "SPACES_ACCESS_KEY_ID=${{ secrets.SPACES_ACCESS_KEY_ID }}",
    "SPACES_SECRET_ACCESS_KEY=${{ secrets.SPACES_SECRET_ACCESS_KEY }}",
    "SPACES_BUCKET=${{ vars.SPACES_BUCKET }}",
    "SPACES_REGION=${{ vars.SPACES_REGION }}",
    "SPACES_HOST=${{ vars.SPACES_HOST }}",
    "SPACES_PUBLIC_URL_BASE=${{ vars.SPACES_PUBLIC_URL_BASE }}"
  ]

  for {variant, {deploy_step, rollback_step}} <- @variants do
    test "rollback #{variant} .env writes the same keys and values as deploy, except IMAGE" do
      deploy = env_lines("deploy", unquote(deploy_step))
      rollback = env_lines("rollback", unquote(rollback_step))

      assert Enum.sort(Map.keys(rollback)) == Enum.sort(Map.keys(deploy))
      assert Map.delete(rollback, "IMAGE") == Map.delete(deploy, "IMAGE")
    end

    test "deploy and rollback #{variant} .env ship the Spaces settings" do
      for {workflow, step} <- [
            {"deploy", unquote(deploy_step)},
            {"rollback", unquote(rollback_step)}
          ],
          line <- @spaces_lines do
        [key, value] = String.split(line, "=", parts: 2)

        assert env_lines(workflow, step)[key] == value,
               "#{workflow} step #{inspect(step)} must write #{line}"
      end
    end
  end

  # Returns the `KEY => value` pairs of the `cat > .env <<EOF ... EOF`
  # heredoc inside the workflow step named `step`.
  defp env_lines(workflow, step) do
    text = File.read!(".github/workflows/#{workflow}.yml")
    [_, after_name] = String.split(text, "- name: #{step}\n", parts: 2)
    [_, after_open] = String.split(after_name, "cat > .env <<EOF\n", parts: 2)
    [body, _] = String.split(after_open, ~r/^\s*EOF\s*$/m, parts: 2)

    body
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [key, value] = line |> String.trim() |> String.split("=", parts: 2)
      {key, value}
    end)
  end
end
