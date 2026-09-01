defmodule Mix.Tasks.Marquee.Themes.Backfill do
  use Mix.Task

  alias Marquee.Branding
  alias Marquee.Branding.Theme

  @shortdoc "Backfills missing org themes from a starter preset."

  @moduledoc """
  Creates a starter theme for every non-deleted organization that does not
  yet have one. Useful when seeding a local database after the signup flow
  started attaching themes automatically.

  ## Usage

      mix marquee.themes.backfill
      mix marquee.themes.backfill --preset daybreak
      mix marquee.themes.backfill --dry-run

  ## Options

    * `--preset PRESET_KEY` - one of `mix run -e "IO.inspect Marquee.Branding.Theme.preset_keys()"`.
      Defaults to the platform default (`midnight`).
    * `--dry-run` - print the orgs that would be updated without writing
      anything to the database.

  This task is intended for local development and one-off seeding. Production
  changes should go through a release command, per CLAUDE.md.
  """

  @switches [preset: :string, dry_run: :boolean]
  @aliases [p: :preset, d: :dry_run]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    preset_key = Keyword.get(opts, :preset, Theme.default_preset_key())
    dry_run? = Keyword.get(opts, :dry_run, false)

    case Branding.backfill_missing_themes(preset: preset_key, dry_run: dry_run?) do
      {:ok, summary} ->
        print_summary(summary)

      {:error, :unknown_preset} ->
        Mix.shell().error(
          "Unknown preset #{inspect(preset_key)}. " <>
            "Valid presets: #{Enum.join(Theme.preset_keys(), ", ")}"
        )

        exit({:shutdown, 1})
    end
  end

  defp print_summary(%{orgs: []} = summary) do
    Mix.shell().info("No organizations missing a theme. (preset: #{summary.preset})")
  end

  defp print_summary(%{dry_run?: true} = summary) do
    Mix.shell().info(
      "[dry run] #{length(summary.orgs)} organization(s) would be backfilled " <>
        "with preset #{inspect(summary.preset)}:"
    )

    Enum.each(summary.orgs, &print_org/1)
  end

  defp print_summary(summary) do
    Mix.shell().info(
      "Created #{summary.created} theme(s) using preset #{inspect(summary.preset)}."
    )

    Enum.each(summary.orgs, &print_org/1)

    case summary.failed do
      [] ->
        :ok

      failures ->
        Mix.shell().error("#{length(failures)} organization(s) failed:")

        Enum.each(failures, fn {org, reason} ->
          Mix.shell().error("  - #{org.slug} (#{org.id}): #{inspect(reason)}")
        end)
    end
  end

  defp print_org(org) do
    Mix.shell().info("  - #{org.slug} (#{org.id})")
  end
end
