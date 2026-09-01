defmodule Mix.Tasks.Marquee.PurgeBots do
  use Mix.Task

  @shortdoc "Deletes all bot viewers and their engagement/analytics data."

  @moduledoc """
  Removes all viewers whose email matches `*@*.bot` and all associated
  records: progress, watchlist, favorites, watch history, queue items,
  playback drop-offs, analytics events, viewer subscriptions, and tokens.

      mix marquee.purge_bots              # purge across all orgs
      mix marquee.purge_bots --org prism-plus  # single org only
      mix marquee.purge_bots --dry-run    # show counts without deleting

  """

  import Ecto.Query

  alias Marquee.Repo

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [org: :string, dry_run: :boolean])

    Mix.Task.run("app.start")

    bot_ids = Repo.all(build_bot_query(opts[:org]))

    if bot_ids == [] do
      Mix.shell().info("No bot viewers found.")
    else
      Mix.shell().info("Found #{length(bot_ids)} bot viewers.")

      if opts[:dry_run] do
        print_counts(bot_ids)
      else
        purge(bot_ids)
      end
    end
  end

  defp build_bot_query(nil) do
    from(v in "viewers", where: like(v.email, "%@%.bot"), select: v.id)
  end

  defp build_bot_query(org_slug) do
    from(v in "viewers",
      join: o in "organizations",
      on: o.id == v.organization_id,
      where: like(v.email, "%@%.bot") and o.slug == ^org_slug,
      select: v.id
    )
  end

  defp print_counts(bot_ids) do
    tables = engagement_tables()

    Enum.each(tables, fn {table, fk} ->
      count = Repo.one(from(r in table, where: field(r, ^fk) in ^bot_ids, select: count(r.id)))
      Mix.shell().info("  #{table}: #{count} records")
    end)

    Mix.shell().info("  viewers: #{length(bot_ids)} records")
    Mix.shell().info("\nRun without --dry-run to delete.")
  end

  defp purge(bot_ids) do
    tables = engagement_tables()

    Enum.each(tables, fn {table, fk} ->
      {deleted, _} = Repo.delete_all(from(r in table, where: field(r, ^fk) in ^bot_ids))
      Mix.shell().info("  Deleted #{deleted} from #{table}")
    end)

    {deleted, _} = Repo.delete_all(from(v in "viewers", where: v.id in ^bot_ids))
    Mix.shell().info("  Deleted #{deleted} from viewers")
    Mix.shell().info("\nPurge complete.")
  end

  defp engagement_tables do
    [
      {"progresses", :viewer_id},
      {"watchlist_items", :viewer_id},
      {"favorites", :viewer_id},
      {"watch_histories", :viewer_id},
      {"queue_items", :viewer_id},
      {"playback_drop_offs", :viewer_id},
      {"analytics_events", :viewer_id},
      {"viewer_subscriptions", :viewer_id},
      {"viewer_tokens", :viewer_id}
    ]
  end
end
