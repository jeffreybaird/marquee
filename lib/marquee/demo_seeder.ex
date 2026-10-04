defmodule Marquee.DemoSeeder do
  @moduledoc """
  Seeds fully-populated demo organizations with Pexels video content via Mux.

  Creates 5 demo streaming platforms, each with videos ingested from Pexels
  through Mux, series/seasons/episodes, collections, plans, hero slides,
  landing pages, and catalog rows.

  This is a plain module (no Mix dependency) so it can run in a production
  release via `Marquee.Release.seed_demo/1`. The `mix marquee.seed_demo_orgs`
  task is a thin wrapper around `seed/1` for local development.

  Requires a Pexels API key (passed as `:pexels_key` or read from the
  `PEXELS_API_KEY` env var). Mux credentials must be configured. Pexels videos
  must be at least 2 minutes long. Videos start in "preparing" status — Mux
  webhooks update them to "ready".
  """

  alias Ecto.Adapters.SQL, as: EctoSQL
  alias Marquee.{Accounts, Admin, Billing, Branding, Catalog, Content, LandingPage, Repo, Viewers}
  alias Marquee.Accounts.{Membership, Organization, Scope, User}
  alias Marquee.Billing.Coupon
  alias Marquee.Content.{Collection, Series, Tag, Video}
  alias Marquee.Viewers.Viewer
  alias Mux.Video.Assets, as: MuxAssets

  @pexels_delay_ms 500
  @pexels_min_duration_seconds 120
  @pexels_search_per_page 80
  @pexels_max_search_pages 6
  @mux_delay_ms 1_000
  @mux_max_retries 3

  @roles [:owner, :admin, :editor, :viewer_support]

  @doc """
  Provisions only the Workshop subscriber demo from the reviewed
  `:subscriber_demo_catalog` application configuration. No remote ingestion,
  operator users, sample passwords, plans, or payment records are created.
  Returns `{:error, :media_not_configured}` until a manifest is supplied.
  """
  def seed_subscriber_demo do
    Repo.transaction(fn ->
      definition = Enum.find(org_defs(), &(&1.slug == "the-workshop"))

      org =
        Repo.get_by(Organization, slug: definition.slug) || create_subscriber_demo_org(definition)

      org =
        org
        |> Ecto.Changeset.change(features: Map.put(org.features || %{}, "subscriber_demo", true))
        |> Repo.update!()

      case Marquee.SubscriberDemo.seed_catalog(org) do
        {:ok, catalog} ->
          org = Repo.get!(Organization, org.id)
          apply_theme(org, definition.theme)
          apply_branding(org, definition.branding)
          Map.put(catalog, :organization, org)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp create_subscriber_demo_org(definition) do
    {:ok, org} = Admin.create_organization(nil, %{name: definition.name, slug: definition.slug})
    org
  end

  @doc """
  Seeds the demo organizations.

  Options:

    * `:pexels_key` — Pexels API key. Falls back to the `PEXELS_API_KEY` env
      var; raises when neither is present.
    * `:org` — seed only the org with this slug (default: all 5).
    * `:force` — delete and recreate orgs that already exist (default: false).

  Assumes the application (Repo, PubSub, Req, Mux) is already started; callers
  running outside a booted app must start it first (the Mix task and
  `Marquee.Release.seed_demo/1` both do).
  """
  def seed(opts \\ []) do
    pexels_key =
      opts[:pexels_key] || System.get_env("PEXELS_API_KEY") ||
        raise("PEXELS_API_KEY env var required (or pass :pexels_key)")

    target_slug = opts[:org]
    force? = opts[:force] || false

    org_defs()
    |> filter_orgs(target_slug)
    |> Enum.each(fn org_def ->
      seed_org(org_def, pexels_key, force?)
    end)
  end

  @doc """
  Returns the slugs of the demo organizations this seeder creates, in order.

  ## Examples

      iex> Marquee.DemoSeeder.org_slugs()
      ["wanderlust-tv", "the-workshop", "zenith-fitness", "art-of-war-40k", "prism-plus"]

  """
  def org_slugs, do: Enum.map(org_defs(), & &1.slug)

  defp filter_orgs(defs, nil), do: defs

  defp filter_orgs(defs, slug) do
    case Enum.filter(defs, &(&1.slug == slug)) do
      [] -> raise("Unknown org slug: #{slug}. Valid: #{Enum.map_join(defs, ", ", & &1.slug)}")
      filtered -> filtered
    end
  end

  defp seed_org(org_def, pexels_key, force?) do
    existing = Repo.get_by(Organization, slug: org_def.slug)

    cond do
      existing && force? ->
        IO.puts("\n=== Purging content for #{org_def.name} ===")
        purge_org_content(existing.id)
        do_seed(org_def, pexels_key, existing)

      existing ->
        IO.puts("\n=== Resuming #{org_def.name} (exists, seeding missing content) ===")
        do_seed(org_def, pexels_key, existing)

      true ->
        do_seed(org_def, pexels_key)
    end
  end

  @purge_tables [
    "hero_slides",
    "row_items",
    "rows",
    "landing_sections",
    "collection_items",
    "video_tags",
    "episodes",
    "seasons",
    "series",
    "collections",
    "watchlist_items",
    "favorites",
    "watch_histories",
    "progresses",
    "viewer_subscriptions",
    "subscriptions",
    "queue_items",
    "analytics_events",
    "analytics_snapshots",
    "playback_drop_offs",
    "video_drop_off_buckets",
    "notifications",
    "webhook_endpoints",
    "videos",
    "tags",
    "coupons",
    "plans",
    "viewers",
    "memberships",
    "themes",
    "layouts",
    "platform_subscriptions",
    "audit_logs"
  ]

  defp purge_org_content(org_id) do
    Enum.each(@purge_tables, fn table ->
      %{num_rows: count} =
        EctoSQL.query!(Repo, "DELETE FROM #{table} WHERE organization_id = $1", [
          Ecto.UUID.dump!(org_id)
        ])

      if count > 0, do: IO.puts("    Purged #{count} rows from #{table}")
    end)
  end

  defp do_seed(org_def, pexels_key, existing_org \\ nil) do
    org =
      case existing_org do
        nil ->
          IO.puts("\n=== Creating #{org_def.name} ===")
          {:ok, org} = Admin.create_organization(nil, %{name: org_def.name, slug: org_def.slug})
          org

        org ->
          org
      end

    IO.puts("  Creating demo users...")
    create_demo_users(org)

    IO.puts("  Creating demo viewers...")
    create_demo_viewers(org)

    scope = %Scope{organization: org}

    apply_theme(org, org_def.theme)
    apply_branding(org, org_def.branding)

    IO.puts("  Fetching standalone videos...")
    standalones = create_standalones(scope, org, org_def.standalones, pexels_key)

    series_map = create_all_series(scope, org, org_def.series_defs, pexels_key)

    IO.puts("  Applying tags...")
    apply_tags(scope, org, standalones, org_def.standalones, series_map, org_def.series_defs)

    IO.puts("  Creating collections...")
    collections = create_collections(scope, org_def.collections, standalones, series_map)

    IO.puts("  Creating plans...")
    create_plans(scope, org, org_def.plans)

    if org_def[:coupons], do: create_coupons(org, org_def.coupons)

    IO.puts("  Creating landing page...")
    create_landing_sections(scope, org_def.landing_sections, collections)

    IO.puts("  Creating hero slides...")
    create_hero_slides(scope, org, standalones, org_def.hero_slides)

    IO.puts("  Creating catalog rows...")
    create_catalog_rows(scope, org_def.catalog_rows, collections, series_map)

    IO.puts("  ✓ #{org_def.name} complete")
  end

  # -------------------------------------------------------------------
  # Theme & Branding
  # -------------------------------------------------------------------

  defp apply_theme(org, theme_attrs) do
    case Branding.get_theme_by_org(org) do
      %Branding.Theme{} = theme ->
        Branding.update_theme(nil, theme, theme_attrs)

      nil ->
        Branding.create_theme(nil, Map.put(theme_attrs, :organization_id, org.id))
    end
  end

  defp apply_branding(org, branding_attrs) do
    org
    |> Organization.branding_changeset(branding_attrs)
    |> Repo.update!()
  end

  # -------------------------------------------------------------------
  # Demo Users (one per role)
  # -------------------------------------------------------------------

  defp create_demo_users(org) do
    Enum.each(@roles, fn role ->
      email = "#{role}@#{org.slug}.demo"
      find_or_create_demo_user(org, email, role)
    end)
  end

  defp find_or_create_demo_user(org, email, role) do
    user =
      case Repo.get_by(User, email: email) do
        %User{} = existing ->
          IO.puts("    User exists: #{email}")
          existing

        nil ->
          {:ok, u} = Accounts.register_user(%{email: email})
          IO.puts("    Created user: #{email}")
          u
      end

    case Accounts.get_membership(org, user) do
      %Membership{} ->
        IO.puts("    Membership exists: #{role}")

      nil ->
        %Membership{}
        |> Membership.changeset(%{user_id: user.id, organization_id: org.id, role: role})
        |> Repo.insert!()

        IO.puts("    Added #{role} membership")
    end
  end

  # -------------------------------------------------------------------
  # Demo Viewers (customers of the org)
  # -------------------------------------------------------------------

  @viewer_defs [
    %{name: "alice", display_name: "Alice Demo", subscription_status: "active"},
    %{name: "bob", display_name: "Bob Demo", subscription_status: "trial"},
    %{name: "carol", display_name: "Carol Demo", subscription_status: "none"},
    %{name: "dave", display_name: "Dave Demo", subscription_status: "canceled"},
    %{name: "eve", display_name: "Eve Demo", subscription_status: "expired"}
  ]

  defp create_demo_viewers(org) do
    Enum.each(@viewer_defs, fn vdef ->
      email = "#{vdef.name}@#{org.slug}.demo"

      case Viewers.get_viewer_by_email(org, email) do
        %Viewer{} ->
          IO.puts("    Viewer exists: #{email}")

        nil ->
          {:ok, viewer} =
            Viewers.register_viewer(org, %{
              email: email,
              display_name: vdef.display_name,
              password: "demodemo1234"
            })

          viewer
          |> Viewer.subscription_changeset(%{
            subscription_status: vdef.subscription_status
          })
          |> Repo.update!()

          IO.puts("    Created viewer: #{email} (#{vdef.subscription_status})")
      end
    end)
  end

  # -------------------------------------------------------------------
  # Pexels + Mux video ingestion
  # -------------------------------------------------------------------

  defp create_standalones(scope, org, video_defs, pexels_key) do
    pexels_videos = fetch_pexels_videos(video_defs, pexels_key)

    video_defs
    |> Enum.zip(pexels_videos)
    |> Enum.map(fn {vdef, pexels_video} ->
      find_or_create_video(scope, org, vdef.title, vdef.description, pexels_video,
        visibility: vdef[:visibility] || "public",
        indent: "    "
      )
    end)
  end

  defp maybe_reingest(%Video{mux_asset_id: "pending"} = video, pexels_url) do
    IO.puts("    Re-ingesting: #{video.title} (pending Mux)")
    ingest_to_mux(video, pexels_url)
  end

  defp maybe_reingest(_video, _url), do: :ok

  defp find_or_create_video(
         scope,
         org,
         title,
         description,
         %{url: pexels_url, duration: duration},
         opts
       )
       when duration >= @pexels_min_duration_seconds do
    slug = slugify(title)
    indent = Keyword.get(opts, :indent, "    ")

    case Repo.get_by(Video, slug: slug, organization_id: org.id) do
      %Video{} = existing ->
        IO.puts("#{indent}Exists: #{title}")
        maybe_reingest(existing, pexels_url)
        existing

      nil ->
        IO.puts("#{indent}Ingesting: #{title}")

        {:ok, video} =
          Content.create_video(scope, %{
            title: title,
            slug: slug,
            description: description,
            organization_id: org.id,
            mux_asset_id: "pending",
            mux_playback_id: "pending",
            mux_status: "preparing",
            duration: duration,
            published: true,
            visibility: Keyword.get(opts, :visibility, "public")
          })

        ingest_to_mux(video, pexels_url)
        video
    end
  end

  defp find_or_create_video(_scope, _org, title, _description, pexels_video, _opts) do
    raise("""
    Pexels result for "#{title}" was shorter than #{div(@pexels_min_duration_seconds, 60)} minutes:
    #{inspect(pexels_video)}
    """)
  end

  defp fetch_pexels_videos(video_defs, pexels_key) do
    {cache, _used_urls} =
      video_defs
      |> Enum.map(& &1.search)
      |> Enum.uniq()
      |> Enum.reduce({%{}, MapSet.new()}, fn query, {cache, used_urls} ->
        needed = Enum.count(video_defs, &(&1.search == query))
        videos = search_pexels(query, needed, pexels_key, used_urls)
        used_urls = Enum.reduce(videos, used_urls, &MapSet.put(&2, &1.url))

        {Map.put(cache, query, videos), used_urls}
      end)

    counters = Map.new(cache, fn {k, _} -> {k, 0} end)

    {videos, _} =
      Enum.map_reduce(video_defs, counters, fn vdef, acc ->
        idx = acc[vdef.search]
        pool = cache[vdef.search]
        video = Enum.at(pool, idx)
        {video, Map.put(acc, vdef.search, idx + 1)}
      end)

    videos
  end

  defp search_pexels(query, count, api_key, used_urls) do
    search_results =
      fetch_search_pexels_videos(query, count, api_key, used_urls)

    results =
      if length(search_results) >= count do
        search_results
      else
        IO.puts(
          "    Pexels search for #{inspect(query)} returned #{length(search_results)} long videos; filling with popular long-form videos."
        )

        remaining = count - length(search_results)
        used_urls = Enum.reduce(search_results, used_urls, &MapSet.put(&2, &1.url))
        search_results ++ fetch_popular_pexels_videos(remaining, api_key, used_urls)
      end

    if length(results) < count do
      raise("""
      Pexels returned #{length(results)} videos at least #{div(@pexels_min_duration_seconds, 60)} minutes long for #{inspect(query)}.
      Needed #{count}. Try broader search terms or raise @pexels_max_search_pages.
      """)
    end

    Enum.take(results, count)
  end

  defp fetch_search_pexels_videos(query, count, api_key, used_urls) do
    Enum.reduce_while(1..@pexels_max_search_pages, [], fn page, videos ->
      reduce_pexels_page(videos, count, used_urls, fn ->
        Req.get!("https://api.pexels.com/v1/videos/search",
          params: [
            query: query,
            per_page: @pexels_search_per_page,
            orientation: "landscape",
            page: page
          ],
          headers: [{"Authorization", api_key}]
        )
      end)
    end)
  end

  defp fetch_popular_pexels_videos(count, api_key, used_urls) do
    Enum.reduce_while(1..@pexels_max_search_pages, [], fn page, videos ->
      reduce_pexels_page(videos, count, used_urls, fn ->
        Req.get!("https://api.pexels.com/v1/videos/popular",
          params: [
            per_page: @pexels_search_per_page,
            page: page,
            min_width: 1280,
            min_height: 720,
            min_duration: @pexels_min_duration_seconds
          ],
          headers: [{"Authorization", api_key}]
        )
      end)
    end)
  end

  defp reduce_pexels_page(videos, count, _used_urls, _fetch) when length(videos) >= count,
    do: {:halt, videos}

  defp reduce_pexels_page(videos, count, used_urls, fetch) do
    resp = fetch.()
    Process.sleep(@pexels_delay_ms)

    videos =
      videos
      |> Kernel.++(extract_long_pexels_videos(resp.body, used_urls))
      |> Enum.uniq_by(& &1.url)

    if length(videos) >= count or is_nil(resp.body["next_page"]) do
      {:halt, videos}
    else
      {:cont, videos}
    end
  end

  defp extract_long_pexels_videos(body, used_urls) do
    body
    |> Map.get("videos", [])
    |> Enum.filter(&(pexels_duration(&1) >= @pexels_min_duration_seconds))
    |> Enum.flat_map(&to_pexels_video/1)
    |> Enum.reject(&MapSet.member?(used_urls, &1.url))
  end

  defp to_pexels_video(video) do
    video
    |> Map.get("video_files", [])
    |> Enum.filter(&(&1["quality"] == "hd" && &1["file_type"] == "video/mp4"))
    |> Enum.sort_by(& &1["width"], :desc)
    |> List.first()
    |> case do
      %{"link" => link} when is_binary(link) ->
        [%{url: link, duration: pexels_duration(video)}]

      _ ->
        []
    end
  end

  defp pexels_duration(video), do: Map.get(video, "duration", 0) || 0

  defp ingest_to_mux(video, pexels_url) do
    ingest_to_mux(video, pexels_url, 1)
  end

  defp ingest_to_mux(video, pexels_url, attempt) do
    Process.sleep(@mux_delay_ms)
    client = mux_client()

    case MuxAssets.create(client, %{
           input: [%{url: pexels_url}],
           playback_policy: ["public"],
           video_quality: "plus"
         }) do
      {:ok, asset, _env} ->
        playback_id =
          asset["playback_ids"]
          |> List.first(%{})
          |> Map.get("id", "pending")

        video
        |> Ecto.Changeset.change(%{
          mux_asset_id: asset["id"],
          mux_playback_id: playback_id,
          mux_status: "preparing"
        })
        |> Repo.update!()

      {:error, _type, _messages} ->
        maybe_retry_mux(video, pexels_url, attempt, "API error")
    end
  rescue
    e ->
      maybe_retry_mux(video, pexels_url, attempt, Exception.message(e))
  end

  defp maybe_retry_mux(video, pexels_url, attempt, reason) do
    if attempt < @mux_max_retries do
      backoff = attempt * 2_000
      IO.puts("    ⚠ Mux attempt #{attempt} failed for #{video.title}: #{reason}")
      IO.puts("      Retrying in #{div(backoff, 1_000)}s...")
      Process.sleep(backoff)
      ingest_to_mux(video, pexels_url, attempt + 1)
    else
      IO.puts("    ✗ Mux ingestion failed after #{@mux_max_retries} attempts: #{video.title}")
    end
  end

  defp mux_client do
    token_id = Application.fetch_env!(:marquee, :mux_token_id)
    token_secret = Application.fetch_env!(:marquee, :mux_token_secret)
    Mux.client(token_id, token_secret)
  end

  # -------------------------------------------------------------------
  # Series / Seasons / Episodes
  # -------------------------------------------------------------------

  defp create_all_series(scope, org, series_defs, pexels_key) do
    series_defs
    |> Enum.reduce(%{}, fn sdef, acc ->
      slug = slugify(sdef.title)

      series =
        case Repo.get_by(Series, slug: slug, organization_id: org.id) do
          %Series{} = existing ->
            IO.puts("  Series exists: #{sdef.title}")
            existing

          nil ->
            IO.puts("  Creating series: #{sdef.title}")

            {:ok, s} =
              Content.create_series(scope, %{
                title: sdef.title,
                description: sdef.description,
                new_season: sdef[:new_season] || false
              })

            s
        end

      seasons =
        sdef.seasons
        |> Enum.with_index(1)
        |> Enum.map(&create_season_with_episodes(scope, org, series, sdef, &1, pexels_key))

      Map.put(acc, sdef.key, %{series: series, seasons: seasons})
    end)
  end

  defp create_season_with_episodes(scope, org, series, sdef, {season_def, season_num}, pexels_key) do
    import Ecto.Query, only: [where: 3]

    series_id = series.id

    season_attrs = %{
      title: season_def.title,
      description: season_def[:description] || sdef.description,
      season_number: season_num
    }

    existing_season =
      Marquee.Content.Season
      |> where([s], s.series_id == ^series_id and s.season_number == ^season_num)
      |> Repo.one()

    season =
      case existing_season do
        nil ->
          IO.puts(
            "    Season #{season_num}: #{season_def.title} (#{season_def.episode_count} episodes)"
          )

          create_or_fetch_season(scope, series, season_attrs)

        s ->
          maybe_restore_existing_seed_season(s, season_attrs)
      end

    scope
    |> fetch_and_create_episode_videos(org, season_def, pexels_key)
    |> Enum.with_index(1)
    |> Enum.each(fn {video, ep_num} ->
      title = Enum.at(season_def.episode_titles, ep_num - 1)

      case Content.add_episode(scope, season, video, %{episode_number: ep_num, title: title}) do
        {:ok, _} -> :ok
        {:error, :already_exists} -> :ok
      end
    end)

    season
  end

  defp create_or_fetch_season(scope, series, attrs) do
    case Content.create_season(scope, series, attrs) do
      {:ok, season} ->
        season

      {:error, :validation, changeset} ->
        if season_number_taken?(changeset) do
          Repo.get_by!(Marquee.Content.Season,
            series_id: series.id,
            season_number: attrs.season_number
          )
          |> maybe_restore_existing_seed_season(attrs)
        else
          raise("Could not create seed season: #{inspect(changeset.errors)}")
        end
    end
  end

  defp season_number_taken?(changeset) do
    Enum.any?(changeset.errors, fn
      {:series_id, {_message, opts}} ->
        opts[:constraint_name] == "seasons_series_id_season_number_index"

      _ ->
        false
    end)
  end

  defp maybe_restore_existing_seed_season(%{deleted_at: nil} = season, attrs) do
    IO.puts("    Season #{attrs.season_number} exists: #{season.title}")
    season
  end

  defp maybe_restore_existing_seed_season(season, attrs) do
    IO.puts("    Season #{attrs.season_number} exists: #{season.title}")

    season
    |> Ecto.Changeset.change(%{
      title: attrs.title,
      description: attrs.description,
      visible: true,
      deleted_at: nil
    })
    |> Repo.update!()
  end

  defp fetch_and_create_episode_videos(scope, org, season_def, pexels_key) do
    pexels_videos =
      search_pexels(season_def.search, season_def.episode_count, pexels_key, MapSet.new())

    season_def.episode_titles
    |> Enum.zip(pexels_videos)
    |> Enum.map(fn {title, pexels_video} ->
      description = season_def[:description] || "Episode: #{title}"
      find_or_create_video(scope, org, title, description, pexels_video, indent: "      ")
    end)
  end

  # -------------------------------------------------------------------
  # Tags
  # -------------------------------------------------------------------

  defp apply_tags(scope, org, standalones, standalone_defs, series_map, series_defs) do
    tag_cache = ensure_tags(scope, org, standalone_defs, series_defs)

    standalone_defs
    |> Enum.zip(standalones)
    |> Enum.each(fn {vdef, video} ->
      apply_video_tags(scope, video, vdef[:tags] || [], tag_cache)
    end)

    Enum.each(series_defs, fn sdef ->
      case series_map[sdef.key] do
        nil -> :ok
        %{seasons: seasons} -> tag_series_episodes(scope, org, sdef, seasons, tag_cache)
      end
    end)
  end

  defp apply_video_tags(scope, video, tag_names, tag_cache) do
    Enum.each(tag_names, fn name ->
      tag = tag_cache[String.downcase(name)]
      if tag, do: tag_video_idempotent(scope, video, tag)
    end)
  end

  defp ensure_tags(scope, org, standalone_defs, series_defs) do
    all_tag_names =
      (collect_tag_names(standalone_defs) ++ collect_series_tag_names(series_defs))
      |> Enum.uniq()

    Map.new(all_tag_names, fn name ->
      {String.downcase(name), find_or_create_tag(scope, org, name)}
    end)
  end

  defp collect_tag_names(video_defs) do
    Enum.flat_map(video_defs, fn vdef -> vdef[:tags] || [] end)
  end

  defp collect_series_tag_names(series_defs) do
    series_defs
    |> Enum.flat_map(& &1.seasons)
    |> Enum.flat_map(&(&1[:episode_tags] || []))
    |> Enum.flat_map(fn {_idx, tags} -> tags end)
  end

  defp find_or_create_tag(scope, org, name) do
    slug = slugify(name)

    case Repo.get_by(Tag, slug: slug, organization_id: org.id) do
      %Tag{} = tag -> tag
      nil -> do_create_tag(scope, org, name, slug)
    end
  end

  defp do_create_tag(scope, org, name, slug) do
    case Content.create_tag(scope, %{name: name}) do
      {:ok, tag} -> tag
      {:error, :already_exists} -> Repo.get_by!(Tag, slug: slug, organization_id: org.id)
    end
  end

  defp tag_video_idempotent(scope, video, tag) do
    case Content.tag_video(scope, video, tag) do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp tag_series_episodes(scope, org, sdef, seasons, tag_cache) do
    sdef.seasons
    |> Enum.zip(seasons)
    |> Enum.each(fn {season_def, _season} ->
      Enum.each(season_def[:episode_tags] || [], fn {ep_idx, tags} ->
        tag_episode_by_index(scope, org, season_def, ep_idx, tags, tag_cache)
      end)
    end)
  end

  defp tag_episode_by_index(scope, org, season_def, ep_idx, tags, tag_cache) do
    title = Enum.at(season_def.episode_titles, ep_idx)
    if is_nil(title), do: :ok

    case Repo.get_by(Video, slug: slugify(title), organization_id: org.id) do
      %Video{} = video -> apply_video_tags(scope, video, tags, tag_cache)
      nil -> :ok
    end
  end

  # -------------------------------------------------------------------
  # Collections
  # -------------------------------------------------------------------

  defp create_collections(scope, collection_defs, standalones, series_map) do
    org = scope.organization

    collection_defs
    |> Enum.reduce(%{}, fn cdef, acc ->
      slug = slugify(cdef.title)

      collection =
        case Repo.get_by(Collection, slug: slug, organization_id: org.id) do
          %Collection{} = existing ->
            IO.puts("    Collection exists: #{cdef.title}")
            existing

          nil ->
            {:ok, c} =
              Content.create_collection(scope, %{
                title: cdef.title,
                description: cdef[:description]
              })

            c
        end

      add_collection_items(scope, collection, cdef, standalones, series_map)
      Map.put(acc, cdef.key, collection)
    end)
  end

  defp add_collection_items(scope, collection, cdef, standalones, series_map) do
    Enum.each(cdef.items, &add_collection_item(scope, collection, &1, standalones, series_map))
  end

  defp add_collection_item(scope, collection, {:standalones, :random, count}, standalones, _) do
    standalones
    |> Enum.shuffle()
    |> Enum.take(count)
    |> Enum.each(&Content.add_video_to_collection(scope, collection, &1))
  end

  defp add_collection_item(scope, collection, {:standalones, :recent, count}, standalones, _) do
    standalones
    |> Enum.reverse()
    |> Enum.take(count)
    |> Enum.each(&Content.add_video_to_collection(scope, collection, &1))
  end

  defp add_collection_item(scope, collection, {:standalones, indices}, standalones, _)
       when is_list(indices) do
    indices
    |> Enum.map(&Enum.at(standalones, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.each(&Content.add_video_to_collection(scope, collection, &1))
  end

  defp add_collection_item(scope, collection, {:series, series_key}, _, series_map) do
    case series_map[series_key] do
      %{series: series} -> Content.add_series_to_collection(scope, collection, series)
      _ -> :noop
    end
  end

  defp add_collection_item(scope, collection, {:season, series_key, season_idx}, _, series_map) do
    case series_map[series_key] do
      %{seasons: seasons} ->
        season = Enum.at(seasons, season_idx)
        if season, do: Content.add_season_to_collection(scope, collection, season)

      _ ->
        :noop
    end
  end

  # -------------------------------------------------------------------
  # Plans & Coupons
  # -------------------------------------------------------------------

  defp create_plans(scope, org, plan_defs) do
    existing = Billing.list_plans(org)

    if existing.total > 0 do
      IO.puts("    Plans exist (#{existing.total}), skipping")
    else
      plan_defs
      |> Enum.with_index()
      |> Enum.each(fn {pdef, idx} ->
        {:ok, _} =
          Billing.create_plan(scope, %{
            name: pdef.name,
            description: pdef[:description],
            stripe_price_id: "demo_price_#{org.slug}_#{idx}",
            stripe_product_id: "demo_prod_#{org.slug}_#{idx}",
            amount: pdef.amount,
            currency: "usd",
            interval: pdef.interval,
            trial_period_days: pdef[:trial_days] || 0,
            active: true,
            position: idx,
            features: pdef[:features] || [],
            organization_id: org.id
          })
      end)
    end
  end

  defp create_coupons(org, coupon_defs) do
    IO.puts("  Creating coupons...")

    Enum.each(coupon_defs, fn cdef ->
      code = String.upcase(cdef.code)

      case Repo.get_by(Coupon, code: code, organization_id: org.id) do
        %Coupon{} ->
          IO.puts("    Coupon exists: #{code}")

        nil ->
          attrs =
            %{
              organization_id: org.id,
              code: code,
              name: cdef[:name] || code,
              duration: cdef.duration,
              active: true,
              stripe_coupon_id: "demo_coupon_#{org.slug}_#{code}",
              stripe_promotion_code_id: "demo_promo_#{org.slug}_#{code}"
            }
            |> maybe_put(
              :percent_off,
              cdef[:percent_off] && Decimal.new(to_string(cdef[:percent_off]))
            )
            |> maybe_put(:amount_off, cdef[:amount_off])
            |> maybe_put(:duration_in_months, cdef[:duration_in_months])

          %Coupon{} |> Coupon.changeset(attrs) |> Repo.insert!()
      end
    end)
  end

  # -------------------------------------------------------------------
  # Landing Page
  # -------------------------------------------------------------------

  defp create_landing_sections(scope, section_defs, collections) do
    existing = LandingPage.list_landing_sections_admin(scope.organization)

    if existing.total > 0 do
      IO.puts("    Landing sections exist (#{existing.total}), skipping")
    else
      section_defs
      |> Enum.with_index()
      |> Enum.each(fn {sdef, idx} ->
        config = resolve_landing_config(sdef.config, collections)

        {:ok, _} =
          LandingPage.create_landing_section(scope, %{
            "section_type" => to_string(sdef.type),
            "position" => idx,
            "visible" => true,
            "config" => config
          })
      end)
    end
  end

  defp resolve_landing_config(config, collections) do
    case config do
      %{source_type: "collection", collection_key: key} ->
        collection = collections[key]

        config
        |> Map.delete(:collection_key)
        |> Map.put(:source_id, collection && collection.id)
        |> stringify_keys()

      _ ->
        stringify_keys(config)
    end
  end

  # -------------------------------------------------------------------
  # Hero Slides
  # -------------------------------------------------------------------

  defp create_hero_slides(scope, org, standalones, slide_defs) do
    {:ok, hero_row} =
      case Catalog.get_hero_row(org) do
        {:ok, row} -> {:ok, row}
        {:error, :not_found} -> Catalog.create_hero_row(scope, %{title: "Hero"})
      end

    existing_slides = Catalog.list_hero_slides(org, hero_row)

    if existing_slides != [] do
      IO.puts("    Hero slides exist (#{length(existing_slides)}), skipping")
    else
      Enum.each(Enum.with_index(slide_defs), fn {sdef, idx} ->
        create_single_hero_slide(scope, hero_row, standalones, sdef, idx)
      end)
    end
  end

  defp create_single_hero_slide(scope, hero_row, standalones, sdef, idx) do
    video = Enum.at(standalones, sdef.video_index)

    if video do
      {:ok, _} =
        Catalog.create_hero_slide(scope, hero_row, %{
          video_id: video.id,
          position: idx,
          headline: sdef[:headline],
          subheadline: sdef[:subheadline],
          description: sdef[:description]
        })
    end
  end

  # -------------------------------------------------------------------
  # Catalog Rows
  # -------------------------------------------------------------------

  defp create_catalog_rows(scope, row_defs, collections, _series_map) do
    existing = Catalog.list_rows(scope.organization, per_page: 1)

    if existing.total > 1 do
      IO.puts("    Catalog rows exist (#{existing.total}), skipping")
    else
      row_defs
      |> Enum.with_index()
      |> Enum.each(fn {rdef, idx} ->
        attrs = build_row_attrs(rdef, idx, collections)
        {:ok, _} = Catalog.create_row(scope, attrs)
      end)
    end
  end

  defp build_row_attrs(rdef, idx, collections) do
    %{
      title: rdef.title,
      source_type: rdef.source_type,
      visible: true,
      position: idx + 1,
      max_items: rdef[:max_items] || 20
    }
    |> maybe_put_collection_source(rdef, collections)
    |> maybe_put_card_variant(rdef)
  end

  defp maybe_put_collection_source(attrs, %{collection_key: key}, collections) do
    case collections[key] do
      nil -> attrs
      collection -> Map.put(attrs, :source_id, collection.id)
    end
  end

  defp maybe_put_collection_source(attrs, _, _), do: attrs

  defp maybe_put_card_variant(attrs, %{card_variant: variant}) do
    Map.put(attrs, :card_variant, to_string(variant))
  end

  defp maybe_put_card_variant(attrs, _), do: attrs

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # -------------------------------------------------------------------
  # Org Definitions
  # -------------------------------------------------------------------

  defp org_defs do
    [wanderlust_tv(), the_workshop(), zenith_fitness(), art_of_war_40k(), prism_plus()]
  end

  # ===================================================================
  # Wanderlust TV
  # ===================================================================

  defp wanderlust_tv do
    %{
      name: "Wanderlust TV",
      slug: "wanderlust-tv",
      theme: %{
        background: "#0a0a1a",
        surface: "#141428",
        elevated: "#1e1e38",
        text_primary: "#f0f0f5",
        text_secondary: "#9898b0",
        text_on_accent: "#ffffff",
        brand_primary: "#6b4fa2",
        brand_secondary: "#4a3578",
        brand_primary_hover: "#7d62b5",
        accent: "#d4a853",
        font_heading: "Cormorant Garamond",
        font_body: "Lora",
        border_radius: "0.5rem",
        card_border_radius: "0.75rem",
        border_color: "rgba(255, 255, 255, 0.08)",
        divider_color: "rgba(255, 255, 255, 0.05)",
        nav_background: "rgba(10, 10, 26, 0.92)",
        card_background: "#141428",
        overlay_color: "rgba(0, 0, 0, 0.7)"
      },
      branding: %{
        accent_color_base: "oklch(0.62 0.14 300)",
        accent_color_hover: "oklch(0.68 0.14 300)",
        accent_color_active: "oklch(0.56 0.14 300)",
        accent_color_subtle: "oklch(0.26 0.06 300)",
        display_font: "Cormorant Garamond",
        preset_name: "catalog_cinema"
      },
      standalones: [
        %{
          title: "Sunrise Over Santorini",
          search: "travel landscape aerial",
          description:
            "Golden light spills across whitewashed villages as dawn breaks over the Aegean.",
          tags: ["europe", "aerial", "golden hour"]
        },
        %{
          title: "Coastal Wandering",
          search: "ocean coast drone",
          description: "Following the edge of the world where land meets sea.",
          tags: ["coastal", "drone", "nature"]
        },
        %{
          title: "Desert Horizons",
          search: "travel landscape aerial",
          description: "Endless dunes stretch to the horizon under a blazing sky.",
          tags: ["desert", "aerial", "landscape"]
        },
        %{
          title: "Northern Lights",
          search: "travel landscape aerial",
          description: "The aurora dances above frozen tundra in electric greens and violets.",
          tags: ["arctic", "nature", "night sky"]
        },
        %{
          title: "City After Dark",
          search: "city street night",
          description: "Neon reflections on rain-slicked streets tell stories of urban life.",
          tags: ["urban", "night", "street"]
        },
        %{
          title: "Monsoon Season",
          search: "travel landscape aerial",
          description: "Torrential rains transform the landscape into a lush green paradise.",
          tags: ["asia", "nature", "weather"]
        },
        %{
          title: "Island Hopping",
          search: "ocean coast drone",
          description: "Crystal-clear waters connect a chain of tropical islands.",
          tags: ["tropical", "coastal", "drone"]
        },
        %{
          title: "Ancient Trails",
          search: "travel landscape aerial",
          description: "Footpaths carved by centuries of travelers wind through mountain passes.",
          tags: ["hiking", "mountains", "history"]
        },
        %{
          title: "The Night Market",
          search: "city street night",
          description: "A sensory explosion of street food, lanterns, and bustling crowds.",
          tags: ["asia", "urban", "food", "night"]
        },
        %{
          title: "Fjord Country",
          search: "ocean coast drone",
          description: "Dramatic cliffs plunge into deep blue waters in Scandinavia's heartland.",
          tags: ["europe", "coastal", "nature", "drone"]
        }
      ],
      series_defs: [
        %{
          key: :hidden_coastlines,
          title: "Hidden Coastlines",
          description: "Exploring the world's most dramatic shorelines from above.",
          seasons: [
            %{
              title: "Mediterranean",
              search: "ocean coast aerial",
              episode_count: 4,
              episode_titles: [
                "The Amalfi Edge",
                "Sardinia Wild",
                "Croatian Riviera",
                "Aegean Blues"
              ]
            },
            %{
              title: "Pacific",
              search: "ocean coast aerial",
              episode_count: 4,
              episode_titles: ["Big Sur", "Great Barrier", "Kauai North Shore", "Baja Peninsula"]
            }
          ]
        },
        %{
          key: :mountain_life,
          title: "Mountain Life",
          description:
            "Life at altitude — the communities and landscapes of the world's great ranges.",
          seasons: [
            %{
              title: "The Alps",
              search: "mountains hiking nature",
              episode_count: 6,
              episode_titles: [
                "First Light",
                "The Glacier Trail",
                "Alpine Meadows",
                "Storm Season",
                "Summit Day",
                "Valley Return"
              ]
            }
          ]
        }
      ],
      collections: [
        %{key: :staff_picks, title: "Staff Picks", items: [{:standalones, :random, 5}]},
        %{key: :weekend_escapes, title: "Weekend Escapes", items: [{:standalones, :random, 8}]}
      ],
      plans: [
        %{
          name: "Monthly",
          amount: 999,
          interval: :monthly,
          trial_days: 7,
          description: "Full access, cancel anytime."
        },
        %{
          name: "Annual",
          amount: 8999,
          interval: :yearly,
          trial_days: 7,
          description: "Save 25% with annual billing."
        }
      ],
      coupons: [
        %{code: "EXPLORE50", percent_off: 50, duration: :once, name: "50% off first payment"}
      ],
      landing_sections: [
        %{
          type: :hero_image,
          config: %{
            headline: "Discover the World",
            subheadline: "Cinematic travel stories from every continent."
          }
        },
        %{
          type: :marketing_copy,
          config: %{
            headline: "Your Passport to Wonder",
            body:
              "From hidden coastlines to towering peaks, Wanderlust TV brings the world's most breathtaking destinations to your screen."
          }
        },
        %{
          type: :content_row,
          config: %{source_type: "collection", collection_key: :staff_picks, title: "Staff Picks"}
        },
        %{type: :plan_display, config: %{}},
        %{
          type: :faq,
          config: %{
            items: [
              %{
                question: "Can I download videos for offline viewing?",
                answer:
                  "Yes — subscribers can download any video for offline viewing on mobile devices."
              },
              %{
                question: "How often is new content added?",
                answer: "We publish new episodes every week and add standalone films monthly."
              },
              %{
                question: "Can I cancel anytime?",
                answer: "Absolutely. No contracts, no commitments."
              }
            ]
          }
        }
      ],
      hero_slides: [
        %{
          video_index: 0,
          headline: "Sunrise Over Santorini",
          subheadline: "A cinematic journey through the Aegean."
        },
        %{
          video_index: 3,
          headline: "Northern Lights",
          subheadline: "Nature's greatest light show."
        },
        %{
          video_index: 6,
          headline: "Island Hopping",
          subheadline: "Crystal waters, hidden coves."
        },
        %{video_index: 9, headline: "Fjord Country", subheadline: "Where mountains meet the sea."}
      ],
      catalog_rows: [
        %{title: "New Releases", source_type: :recent},
        %{title: "Staff Picks", source_type: :collection, collection_key: :staff_picks},
        %{title: "Hidden Coastlines", source_type: :new_seasons}
      ]
    }
  end

  # ===================================================================
  # The Workshop
  # ===================================================================

  defp the_workshop do
    %{
      name: "The Workshop",
      slug: "the-workshop",
      theme: %{
        background: "#0f0b08",
        surface: "#1a1510",
        elevated: "#252015",
        text_primary: "#f5f0e8",
        text_secondary: "#a09880",
        text_on_accent: "#ffffff",
        brand_primary: "#c4941a",
        brand_secondary: "#9a7515",
        brand_primary_hover: "#d4a42a",
        accent: "#c4941a",
        font_heading: "DM Serif Display",
        font_body: "Source Serif 4",
        border_radius: "0.375rem",
        card_border_radius: "0.5rem",
        border_color: "rgba(255, 255, 255, 0.06)",
        divider_color: "rgba(255, 255, 255, 0.04)",
        nav_background: "rgba(15, 11, 8, 0.92)",
        card_background: "#1a1510",
        overlay_color: "rgba(0, 0, 0, 0.75)"
      },
      branding: %{
        accent_color_base: "oklch(0.68 0.14 80)",
        accent_color_hover: "oklch(0.74 0.14 80)",
        accent_color_active: "oklch(0.62 0.14 80)",
        accent_color_subtle: "oklch(0.28 0.06 80)",
        display_font: "DM Serif Display",
        preset_name: "learning_platform"
      },
      standalones: [
        %{
          title: "Building a Dovetail Box",
          search: "woodworking crafting handmade",
          description: "Master the dovetail joint with this step-by-step guide.",
          tags: ["joinery", "beginner", "projects"]
        },
        %{
          title: "Router Fundamentals",
          search: "woodworking crafting handmade",
          description: "Everything you need to know about getting started with a router.",
          tags: ["power tools", "beginner", "technique"]
        },
        %{
          title: "Hand-Cut Joinery",
          search: "woodworking crafting handmade",
          description: "Traditional hand-cut joints that stand the test of time.",
          tags: ["joinery", "hand tools", "traditional"]
        },
        %{
          title: "Finishing Techniques",
          search: "woodworking crafting handmade",
          description: "Oils, stains, and lacquers — choosing the right finish for your project.",
          tags: ["finishing", "technique"]
        },
        %{
          title: "Shop Organization",
          search: "tools equipment workshop",
          description: "A well-organized shop is a productive shop.",
          tags: ["shop setup", "beginner"]
        },
        %{
          title: "Sharpening Essentials",
          search: "tools equipment workshop",
          description: "A sharp tool is a safe tool. Learn proper sharpening technique.",
          tags: ["hand tools", "technique", "maintenance"]
        },
        %{
          title: "Wood Selection Guide",
          search: "woodworking crafting handmade",
          description: "Understanding grain, hardness, and figure for better project outcomes.",
          tags: ["materials", "beginner"]
        },
        %{
          title: "Glue-Up Strategies",
          search: "woodworking crafting handmade",
          description: "Complex glue-ups made simple with proper planning and technique.",
          tags: ["technique", "intermediate"]
        }
      ],
      series_defs: [
        %{
          key: :beginner_woodworking,
          title: "Beginner Woodworking",
          description: "From raw lumber to finished project — the complete beginner's journey.",
          seasons: [
            %{
              title: "Fundamentals",
              search: "woodworking tools workshop",
              episode_count: 8,
              episode_titles: [
                "Your First Cuts",
                "Measuring & Marking",
                "Hand Plane Basics",
                "Chisel Work",
                "Squaring Stock",
                "Simple Joints",
                "First Project: Cutting Board",
                "Your Workbench"
              ]
            }
          ]
        },
        %{
          key: :advanced_projects,
          title: "Advanced Projects",
          description: "Complex builds that push your skills to the next level.",
          seasons: [
            %{
              title: "Tables & Desks",
              search: "furniture building",
              episode_count: 5,
              episode_titles: [
                "Dining Table Design",
                "Leg Construction",
                "Tabletop Glue-Up",
                "Apron Assembly",
                "Final Finishing"
              ]
            },
            %{
              title: "Cabinets & Shelving",
              search: "furniture building",
              episode_count: 5,
              episode_titles: [
                "Carcass Construction",
                "Face Frames",
                "Door Making",
                "Drawer Building",
                "Hardware & Install"
              ]
            }
          ]
        },
        %{
          key: :tool_reviews,
          title: "Tool Reviews",
          description: "Honest, in-depth reviews of hand and power tools.",
          new_season: true,
          seasons: [
            %{
              title: "Hand Tools",
              search: "tools equipment workshop",
              episode_count: 4,
              episode_titles: [
                "Block Planes Compared",
                "Marking Gauges",
                "Japanese Saws",
                "Chisels Under $50"
              ]
            }
          ]
        }
      ],
      collections: [
        %{key: :start_here, title: "Start Here", items: [{:standalones, [0, 1, 2, 4, 5]}]},
        %{key: :under_30, title: "Under 30 Minutes", items: [{:standalones, [0, 2, 3, 5, 6, 7]}]}
      ],
      plans: [
        %{
          name: "Monthly",
          amount: 799,
          interval: :monthly,
          trial_days: 14,
          description: "Full access to all tutorials and reviews."
        },
        %{
          name: "Annual",
          amount: 6999,
          interval: :yearly,
          trial_days: 14,
          description: "Save 27% with annual billing."
        }
      ],
      landing_sections: [
        %{
          type: :hero_image,
          config: %{
            headline: "Build Something Real",
            subheadline: "Expert woodworking tutorials for every skill level."
          }
        },
        %{
          type: :content_row,
          config: %{source_type: "collection", collection_key: :start_here, title: "Start Here"}
        },
        %{type: :plan_display, config: %{}}
      ],
      hero_slides: [
        %{
          video_index: 0,
          headline: "Building a Dovetail Box",
          subheadline: "Classic joinery, step by step."
        },
        %{
          video_index: 1,
          headline: "Router Fundamentals",
          subheadline: "Master the most versatile power tool."
        },
        %{
          video_index: 2,
          headline: "Hand-Cut Joinery",
          subheadline: "Traditional techniques, lasting results."
        }
      ],
      catalog_rows: [
        %{title: "Recently Added", source_type: :recent},
        %{title: "Start Here", source_type: :collection, collection_key: :start_here},
        %{title: "Tool Reviews", source_type: :new_seasons}
      ]
    }
  end

  # ===================================================================
  # Zenith Fitness
  # ===================================================================

  defp zenith_fitness do
    %{
      name: "Zenith Fitness",
      slug: "zenith-fitness",
      theme: %{
        background: "#080f0a",
        surface: "#101a12",
        elevated: "#18251a",
        text_primary: "#f0f5f0",
        text_secondary: "#88a890",
        text_on_accent: "#ffffff",
        brand_primary: "#2d8a4e",
        brand_secondary: "#1f6b3a",
        brand_primary_hover: "#38a05c",
        accent: "#2d8a4e",
        font_heading: "Playfair Display",
        font_body: "Lora",
        border_radius: "0.5rem",
        card_border_radius: "0.75rem",
        border_color: "rgba(255, 255, 255, 0.06)",
        divider_color: "rgba(255, 255, 255, 0.04)",
        nav_background: "rgba(8, 15, 10, 0.92)",
        card_background: "#101a12",
        overlay_color: "rgba(0, 0, 0, 0.7)"
      },
      branding: %{
        accent_color_base: "oklch(0.58 0.16 150)",
        accent_color_hover: "oklch(0.64 0.16 150)",
        accent_color_active: "oklch(0.52 0.16 150)",
        accent_color_subtle: "oklch(0.24 0.06 150)",
        display_font: "Playfair Display",
        preset_name: "catalog_cinema"
      },
      standalones: [
        %{
          title: "Morning Sun Salutation",
          search: "yoga morning stretching",
          description: "Start your day with this energizing sun salutation sequence.",
          tags: ["yoga", "morning", "beginner"]
        },
        %{
          title: "Power Vinyasa Flow",
          search: "yoga fitness meditation wellness",
          description: "A challenging vinyasa flow to build strength and flexibility.",
          tags: ["yoga", "advanced", "strength"]
        },
        %{
          title: "Core Strength Builder",
          search: "fitness exercise bodyweight",
          description: "Targeted core exercises for stability and power.",
          tags: ["strength", "core", "intermediate"]
        },
        %{
          title: "Deep Stretch Recovery",
          search: "yoga morning stretching",
          description: "Gentle stretches to release tension and improve recovery.",
          tags: ["recovery", "stretching", "beginner"]
        },
        %{
          title: "HIIT Cardio Blast",
          search: "fitness exercise bodyweight",
          description: "High-intensity intervals to boost endurance and burn calories.",
          tags: ["hiit", "cardio", "advanced"]
        },
        %{
          title: "Meditation for Focus",
          search: "yoga fitness meditation wellness",
          description: "A guided meditation to sharpen concentration and calm the mind.",
          tags: ["meditation", "mindfulness", "beginner"]
        },
        %{
          title: "Full Body Mobility",
          search: "yoga morning stretching",
          description: "Improve range of motion with this comprehensive mobility routine.",
          tags: ["mobility", "stretching", "recovery"]
        },
        %{
          title: "Balance & Stability",
          search: "fitness exercise bodyweight",
          description: "Challenge your balance with these progressive stability exercises.",
          tags: ["balance", "core", "intermediate"]
        },
        %{
          title: "Evening Wind Down",
          search: "yoga fitness meditation wellness",
          description: "A calming practice to release the day and prepare for rest.",
          tags: ["yoga", "recovery", "evening"]
        },
        %{
          title: "Breath Work Basics",
          search: "yoga fitness meditation wellness",
          description: "Foundational breathing techniques for stress management.",
          tags: ["meditation", "breathwork", "beginner"]
        },
        %{
          title: "Warrior Series",
          search: "yoga morning stretching",
          description: "Build lower body strength through the warrior pose progression.",
          tags: ["yoga", "strength", "intermediate"]
        },
        %{
          title: "Sculpt & Tone",
          search: "fitness exercise bodyweight",
          description: "Bodyweight exercises focused on lean muscle definition.",
          tags: ["strength", "toning", "intermediate"]
        }
      ],
      series_defs: [
        %{
          key: :morning_flow,
          title: "Morning Flow",
          description: "A progressive yoga program designed for morning practice.",
          seasons: [
            %{
              title: "Foundations",
              search: "yoga morning stretching",
              episode_count: 6,
              description: "Building blocks for a sustainable morning practice.",
              episode_titles: [
                "Setting Intention",
                "Sun Salutation A",
                "Sun Salutation B",
                "Standing Poses",
                "Seated Forward Folds",
                "Final Relaxation"
              ]
            },
            %{
              title: "Building Strength",
              search: "yoga morning stretching",
              episode_count: 6,
              description: "Adding power and endurance to your morning flow.",
              episode_titles: [
                "Arm Balances Intro",
                "Core Integration",
                "Hip Openers",
                "Backbend Prep",
                "Flow Sequences",
                "Power Flow"
              ]
            },
            %{
              title: "Advanced Flow",
              search: "yoga morning stretching",
              episode_count: 6,
              description: "Challenging sequences for experienced practitioners.",
              episode_titles: [
                "Inversions",
                "Advanced Binds",
                "Peak Poses",
                "Creative Sequencing",
                "Meditation Integration",
                "Full Practice"
              ]
            }
          ]
        },
        %{
          key: :strength_foundations,
          title: "Strength Foundations",
          description: "Build functional strength with progressive bodyweight training.",
          seasons: [
            %{
              title: "Full Program",
              search: "fitness exercise bodyweight",
              episode_count: 10,
              description: "A complete 10-session strength building program.",
              episode_titles: [
                "Assessment",
                "Push Foundations",
                "Pull Foundations",
                "Squat Mechanics",
                "Hinge Patterns",
                "Core Stability",
                "Upper Body Circuit",
                "Lower Body Circuit",
                "Full Body Integration",
                "Progress Testing"
              ]
            }
          ]
        }
      ],
      collections: [
        %{
          key: :quick_sessions,
          title: "Quick Sessions",
          items: [{:standalones, [0, 2, 4, 7, 9, 11]}]
        },
        %{
          key: :beginner_friendly,
          title: "Beginner Friendly",
          items: [{:standalones, [0, 3, 5, 6, 8, 9, 10, 2]}]
        }
      ],
      plans: [
        %{
          name: "Monthly",
          amount: 1299,
          interval: :monthly,
          trial_days: 7,
          description: "Unlimited access to all classes."
        },
        %{
          name: "Annual",
          amount: 11_999,
          interval: :yearly,
          trial_days: 7,
          description: "Save 23% with annual billing."
        },
        %{
          name: "Premium Monthly",
          amount: 1999,
          interval: :monthly,
          description: "Everything in Monthly plus premium features.",
          features: ["4K streaming", "Offline downloads"]
        }
      ],
      landing_sections: [
        %{
          type: :hero_image,
          config: %{
            headline: "Move With Purpose",
            subheadline: "Yoga, fitness, and wellness — on your schedule."
          }
        },
        %{
          type: :marketing_copy,
          config: %{
            headline: "Your Practice, Your Pace",
            body:
              "From morning flows to evening recovery, Zenith Fitness offers expert-led classes for every level and every body."
          }
        },
        %{
          type: :content_row,
          config: %{
            source_type: "collection",
            collection_key: :quick_sessions,
            title: "Quick Sessions"
          }
        },
        %{type: :plan_display, config: %{}},
        %{
          type: :faq,
          config: %{
            items: [
              %{
                question: "What equipment do I need?",
                answer:
                  "Just a yoga mat for most classes. Some strength sessions use optional resistance bands."
              },
              %{
                question: "Are classes suitable for beginners?",
                answer:
                  "Yes! Our Beginner Friendly collection is designed for those just starting out."
              },
              %{
                question: "How long are the classes?",
                answer: "Classes range from 10-minute quick sessions to 60-minute full practices."
              }
            ]
          }
        }
      ],
      hero_slides: [
        %{
          video_index: 0,
          headline: "Morning Sun Salutation",
          subheadline: "Start your day right."
        },
        %{video_index: 1, headline: "Power Vinyasa Flow", subheadline: "Challenge yourself."},
        %{video_index: 5, headline: "Meditation for Focus", subheadline: "Calm your mind."},
        %{video_index: 8, headline: "Evening Wind Down", subheadline: "Rest and recover."}
      ],
      catalog_rows: [
        %{title: "Featured", source_type: :recent},
        %{title: "Quick Sessions", source_type: :collection, collection_key: :quick_sessions},
        %{title: "Morning Flow", source_type: :series}
      ]
    }
  end

  # ===================================================================
  # Art of War 40K
  # ===================================================================

  defp art_of_war_40k do
    %{
      name: "Art of War 40K",
      slug: "art-of-war-40k",
      theme: %{
        background: "#050507",
        surface: "#111217",
        elevated: "#1b1d25",
        text_primary: "#f6f0e6",
        text_secondary: "#a9a092",
        text_on_accent: "#120f0b",
        brand_primary: "#b91c1c",
        brand_secondary: "#7f1d1d",
        brand_primary_hover: "#dc2626",
        accent: "#d6a84f",
        font_heading: "Bodoni Moda",
        font_body: "Inter",
        border_radius: "0.375rem",
        card_border_radius: "0.5rem",
        border_color: "rgba(214, 168, 79, 0.14)",
        divider_color: "rgba(255, 255, 255, 0.06)",
        nav_background: "rgba(5, 5, 7, 0.94)",
        card_background: "#111217",
        overlay_color: "rgba(0, 0, 0, 0.78)"
      },
      branding: %{
        accent_color_base: "oklch(0.72 0.14 78)",
        accent_color_hover: "oklch(0.78 0.14 78)",
        accent_color_active: "oklch(0.64 0.14 78)",
        accent_color_subtle: "oklch(0.25 0.07 78)",
        display_font: "Bodoni Moda",
        preset_name: "catalog_cinema"
      },
      standalones: [
        %{
          title: "Command Phase: Reading the Mission",
          search: "strategy board game players",
          description:
            "A top-table breakdown of primary scoring, secondary pressure, and when to pivot.",
          tags: ["strategy", "mission play", "competitive"]
        },
        %{
          title: "Deployment Geometry",
          search: "strategy board game players",
          description:
            "How angles, reserves, and threat ranges shape the first two turns before dice roll.",
          tags: ["deployment", "fundamentals", "competitive"]
        },
        %{
          title: "Trading Up: Resource Exchanges",
          search: "strategy board game players",
          description:
            "A practical clinic on sacrificing the right unit to unlock the winning board state.",
          tags: ["resource trading", "advanced", "strategy"]
        },
        %{
          title: "Objective Pressure Clinic",
          search: "strategy board game players",
          description:
            "Layering screens, actions, and late-game bodies to keep pressure on every marker.",
          tags: ["objectives", "mission play", "fundamentals"]
        },
        %{
          title: "Dice Math Under Fire",
          search: "dice board game",
          description:
            "Fast probability shortcuts for choosing the right target under tournament time.",
          tags: ["dice math", "fundamentals", "tournament"]
        },
        %{
          title: "List Doctor: Armored Spearheads",
          search: "military strategy map",
          description:
            "Tuning a vehicle-heavy roster for scoring, redundancy, and matchup coverage.",
          tags: ["list building", "armor", "meta"]
        },
        %{
          title: "Meta Watch: Dataslate Reactions",
          search: "futuristic technology",
          description:
            "What changed, what matters, and which archetypes are ready for the next event.",
          tags: ["meta", "dataslate", "analysis"]
        },
        %{
          title: "Terrain School: Firing Lanes",
          search: "tabletop board game strategy",
          description:
            "Reading ruins, obscuring angles, and staging lanes before the first command point is spent.",
          tags: ["terrain", "fundamentals", "positioning"]
        },
        %{
          title: "Paint Desk: Battle-Ready Infantry",
          search: "painting workshop art",
          description:
            "A clean, repeatable workflow for getting a full unit ready for the tabletop.",
          tags: ["hobby", "painting", "beginner"]
        },
        %{
          title: "Brush Control for Edge Highlights",
          search: "painting workshop art",
          description:
            "Sharper armor plates, cleaner weapons, and faster finishing passes for tournament armies.",
          tags: ["hobby", "painting", "technique"]
        },
        %{
          title: "Tournament Prep: The Night Before",
          search: "people board game",
          description:
            "Packing lists, practice priorities, matchup notes, and the calm before round one.",
          tags: ["tournament", "preparation", "mindset"]
        },
        %{
          title: "Sportsmanship at the Top Table",
          search: "board game players",
          description:
            "Clear intent, clean measurements, and how great opponents keep hard games fair.",
          tags: ["sportsmanship", "tournament", "mindset"]
        },
        %{
          title: "Practice Pods and Reps",
          search: "chess strategy board game",
          description:
            "Building a local training loop that turns casual games into measurable improvement.",
          tags: ["practice", "team room", "coaching"]
        },
        %{
          title: "Clock Discipline",
          search: "chess strategy board game",
          description:
            "Timeboxing decisions, planning the opponent turn, and finishing strong under pressure.",
          tags: ["clock management", "tournament", "advanced"]
        }
      ],
      series_defs: [
        %{
          key: :command_phase_live,
          title: "Command Phase Live",
          description:
            "Round-by-round competitive coaching focused on board state, scoring windows, and pressure.",
          new_season: true,
          seasons: [
            %{
              title: "Primary Plans",
              search: "strategy board game players",
              episode_count: 8,
              description: "Foundational turns for taking space without giving the game away.",
              episode_titles: [
                "Hold Two, Threaten More",
                "The Safe Aggression Turn",
                "Screening for Future Points",
                "When to Abandon a Flank",
                "Trading on Your Terms",
                "The Midboard Trap",
                "Late Primary Swings",
                "Scoring Through Attrition"
              ],
              episode_tags: [
                {0, ["mission play", "fundamentals"]},
                {1, ["positioning", "strategy"]},
                {2, ["screening", "fundamentals"]},
                {3, ["advanced", "mission play"]},
                {4, ["resource trading", "strategy"]},
                {5, ["positioning", "advanced"]},
                {6, ["objectives", "tournament"]},
                {7, ["competitive", "analysis"]}
              ]
            },
            %{
              title: "Pressure Turns",
              search: "strategy board game players",
              episode_count: 8,
              description: "Decision points for turning small advantages into match wins.",
              episode_titles: [
                "The Go Turn",
                "Baiting Overcommitment",
                "Counterpunch Lanes",
                "Denying the Easy Secondary",
                "Surgical Deep Strike",
                "The Sacrifice Screen",
                "Playing From Behind",
                "Closing Without Drama"
              ],
              episode_tags: [
                {0, ["advanced", "tournament"]},
                {1, ["positioning", "strategy"]},
                {2, ["resource trading", "advanced"]},
                {3, ["mission play", "competitive"]},
                {4, ["deployment", "advanced"]},
                {5, ["screening", "fundamentals"]},
                {6, ["mindset", "strategy"]},
                {7, ["clock management", "tournament"]}
              ]
            }
          ]
        },
        %{
          key: :faction_masterclass,
          title: "Faction Masterclass",
          description:
            "Archetype lessons for competitive tabletop armies, from pressure builds to durable castles.",
          seasons: [
            %{
              title: "Archetypes",
              search: "tabletop board game strategy",
              episode_count: 12,
              description:
                "How to identify the plan, stress points, and counterplay for each style.",
              episode_titles: [
                "Pressure Armies",
                "Durable Midboard Bricks",
                "Fast Trading Pieces",
                "Shooting Castles",
                "Board Control Swarms",
                "Elite Melee Hammers",
                "Deep Strike Toolkits",
                "Monster Mash",
                "Vehicle Skew",
                "Tech Pieces That Matter",
                "Balanced Take-All-Comers",
                "Counter-Meta Builds"
              ],
              episode_tags: [
                {0, ["faction focus", "pressure"]},
                {1, ["faction focus", "durability"]},
                {2, ["resource trading", "faction focus"]},
                {3, ["shooting", "positioning"]},
                {4, ["board control", "fundamentals"]},
                {5, ["melee", "advanced"]},
                {6, ["deployment", "advanced"]},
                {7, ["list building", "meta"]},
                {8, ["armor", "list building"]},
                {9, ["tech pieces", "competitive"]},
                {10, ["list building", "tournament"]},
                {11, ["meta", "analysis"]}
              ]
            }
          ]
        },
        %{
          key: :tournament_war_room,
          title: "Tournament War Room",
          description:
            "A full event preparation series for players aiming to make the final table.",
          seasons: [
            %{
              title: "Five Round Run",
              search: "chess tournament strategy",
              episode_count: 8,
              description: "From pairings to final standings, every round needs a plan.",
              episode_titles: [
                "Round One Information",
                "Pairing Into Pressure",
                "Lunch Break Adjustments",
                "Protecting a 2-0 Start",
                "The Undefeated Mirror",
                "Fatigue and Focus",
                "Final Round Math",
                "After-Action Review"
              ],
              episode_tags: [
                {0, ["tournament", "mindset"]},
                {1, ["matchups", "strategy"]},
                {2, ["preparation", "analysis"]},
                {3, ["tournament", "advanced"]},
                {4, ["matchups", "competitive"]},
                {5, ["mindset", "clock management"]},
                {6, ["objectives", "tournament"]},
                {7, ["practice", "coaching"]}
              ]
            }
          ]
        },
        %{
          key: :hobby_forge,
          title: "Hobby Forge",
          description:
            "Painting, basing, and presentation lessons for armies that look sharp across the table.",
          seasons: [
            %{
              title: "Tabletop Ready",
              search: "painting workshop art",
              episode_count: 8,
              description: "Efficient hobby systems for competitive players with limited time.",
              episode_titles: [
                "Scheme Planning",
                "Batch Painting Infantry",
                "Vehicles Without Burnout",
                "Fast Metallics",
                "Readable Bases",
                "Character Centerpieces",
                "Tournament Display Boards",
                "Repair Kit Essentials"
              ],
              episode_tags: [
                {0, ["hobby", "painting"]},
                {1, ["hobby", "beginner"]},
                {2, ["hobby", "armor"]},
                {3, ["painting", "technique"]},
                {4, ["hobby", "presentation"]},
                {5, ["painting", "advanced"]},
                {6, ["tournament", "presentation"]},
                {7, ["preparation", "hobby"]}
              ]
            }
          ]
        }
      ],
      collections: [
        %{
          key: :start_competing,
          title: "Start Competing",
          description: "Core lessons for turning casual reps into clean tournament habits.",
          items: [{:standalones, [0, 1, 2, 3]}, {:season, :command_phase_live, 0}]
        },
        %{
          key: :faction_school,
          title: "Faction School",
          description: "Archetype plans, counters, and list-building principles.",
          items: [{:series, :faction_masterclass}]
        },
        %{
          key: :tournament_weekend,
          title: "Tournament Weekend",
          description: "Prep, pairings, clocks, and mindset for multi-round events.",
          items: [{:standalones, [4, 5, 6, 10, 11, 13]}, {:series, :tournament_war_room}]
        },
        %{
          key: :hobby_and_tables,
          title: "Hobby and Tables",
          description: "Paint desk systems and terrain-reading lessons for better games.",
          items: [{:standalones, [7, 8, 9]}, {:series, :hobby_forge}]
        },
        %{
          key: :staff_picks,
          title: "Coach Picks",
          description: "The lessons our coaches recommend before your next event.",
          items: [
            {:standalones, [0, 3, 6, 12]},
            {:season, :command_phase_live, 1},
            {:season, :faction_masterclass, 0}
          ]
        }
      ],
      plans: [
        %{
          name: "Monthly",
          amount: 1499,
          interval: :monthly,
          trial_days: 7,
          description: "Full access to coaching shows, faction clinics, and hobby lessons."
        },
        %{
          name: "Annual",
          amount: 14_999,
          interval: :yearly,
          trial_days: 7,
          description: "Save with a full year of competitive training."
        },
        %{
          name: "Team Room",
          amount: 2999,
          interval: :monthly,
          description: "For clubs and practice pods building a shared training library.",
          features: ["Team study queues", "Tournament prep playlists", "Coach pick collections"]
        }
      ],
      coupons: [
        %{
          code: "WARROOM25",
          percent_off: 25,
          duration: :repeating,
          duration_in_months: 3,
          name: "War Room launch discount"
        }
      ],
      landing_sections: [
        %{
          type: :hero_image,
          config: %{
            headline: "Win the Mission Before the Last Roll",
            subheadline:
              "Competitive tabletop strategy, faction clinics, and tournament prep for serious players."
          }
        },
        %{
          type: :marketing_copy,
          config: %{
            headline: "Coaching for the Competitive Table",
            body:
              "Art of War 40K turns battle reports, list labs, and practice reps into a structured training library for players chasing cleaner decisions."
          }
        },
        %{
          type: :content_row,
          config: %{
            source_type: "collection",
            collection_key: :start_competing,
            title: "Start Competing"
          }
        },
        %{
          type: :content_row,
          config: %{
            source_type: "collection",
            collection_key: :tournament_weekend,
            title: "Tournament Weekend"
          }
        },
        %{type: :plan_display, config: %{}},
        %{
          type: :faq,
          config: %{
            items: [
              %{
                question: "Is this for new competitive players?",
                answer:
                  "Yes. Start Competing covers the basics while advanced series dig into top-table decisions."
              },
              %{
                question: "Do you cover hobby content too?",
                answer:
                  "Yes. Hobby Forge focuses on efficient painting and presentation for tournament armies."
              },
              %{
                question: "How often is the meta content refreshed?",
                answer:
                  "Meta and dataslate analysis is designed to rotate around major balance updates and events."
              }
            ]
          }
        }
      ],
      hero_slides: [
        %{
          video_index: 0,
          headline: "Command Phase: Reading the Mission",
          subheadline: "Score first. Trade clean. Close late."
        },
        %{
          video_index: 5,
          headline: "List Doctor: Armored Spearheads",
          subheadline: "Redundancy, pressure, and hard targets."
        },
        %{
          video_index: 8,
          headline: "Paint Desk: Battle-Ready Infantry",
          subheadline: "A full unit, table-ready and sharp."
        },
        %{
          video_index: 12,
          headline: "Practice Pods and Reps",
          subheadline: "Turn every game into better decisions."
        }
      ],
      catalog_rows: [
        %{title: "Continue Watching", source_type: :continue_watching},
        %{title: "New Lessons", source_type: :recent, max_items: 24},
        %{
          title: "Start Competing",
          source_type: :collection,
          collection_key: :start_competing,
          max_items: 24
        },
        %{
          title: "Faction School",
          source_type: :collection,
          collection_key: :faction_school,
          max_items: 24
        },
        %{
          title: "Tournament Weekend",
          source_type: :collection,
          collection_key: :tournament_weekend,
          max_items: 24
        },
        %{
          title: "Command Phase Live",
          source_type: :new_seasons,
          max_items: 24
        },
        %{
          title: "Coach Picks",
          source_type: :collection,
          collection_key: :staff_picks,
          max_items: 24
        }
      ]
    }
  end

  # ===================================================================
  # Prism+
  # ===================================================================

  defp prism_plus do
    %{
      name: "Prism+",
      slug: "prism-plus",
      theme: %{
        background: "#08090e",
        surface: "#12141c",
        elevated: "#1c1e28",
        text_primary: "#f0f2f8",
        text_secondary: "#8890a8",
        text_on_accent: "#ffffff",
        brand_primary: "#0ea5e9",
        brand_secondary: "#0284c7",
        brand_primary_hover: "#38bdf8",
        accent: "#0ea5e9",
        font_heading: "DM Serif Display",
        font_body: "Inter",
        border_radius: "0.5rem",
        card_border_radius: "0.75rem",
        border_color: "rgba(255, 255, 255, 0.06)",
        divider_color: "rgba(255, 255, 255, 0.04)",
        nav_background: "rgba(8, 9, 14, 0.92)",
        card_background: "#12141c",
        overlay_color: "rgba(0, 0, 0, 0.75)"
      },
      branding: %{
        accent_color_base: "oklch(0.65 0.18 230)",
        accent_color_hover: "oklch(0.71 0.18 230)",
        accent_color_active: "oklch(0.59 0.18 230)",
        accent_color_subtle: "oklch(0.26 0.08 230)",
        display_font: "DM Serif Display",
        preset_name: "catalog_cinema"
      },
      standalones: [
        %{
          title: "The Last Signal",
          search: "cinematic short film",
          description: "A radio operator receives a transmission that changes everything.",
          tags: ["sci-fi", "short film", "new"]
        },
        %{
          title: "Neon District",
          search: "dramatic scene",
          description: "In a city that never sleeps, one detective works the beat alone.",
          tags: ["crime", "drama", "noir"]
        },
        %{
          title: "Paper Lanterns",
          search: "dramatic scene",
          description: "Two strangers connect over shared memories at a festival of lights.",
          tags: ["drama", "romance"]
        },
        %{
          title: "Cold Open",
          search: "thriller suspense",
          description: "The first five minutes will keep you guessing until the end.",
          tags: ["thriller", "suspense", "new"]
        },
        %{
          title: "The Getaway",
          search: "action scene",
          description: "A heist gone wrong leads to a cross-country chase.",
          tags: ["action", "crime", "heist"]
        },
        %{
          title: "Second Chances",
          search: "dramatic scene",
          description: "A former athlete returns to the sport that nearly destroyed them.",
          tags: ["drama", "sports", "inspirational"]
        },
        %{
          title: "After Midnight",
          search: "thriller suspense",
          description: "Strange things happen in this town after the clock strikes twelve.",
          tags: ["thriller", "horror", "mystery"]
        },
        %{
          title: "Iron Valley",
          search: "action scene",
          description: "In a dying steel town, one family fights to keep the furnace burning.",
          tags: ["drama", "action", "family"]
        },
        %{
          title: "Glass City",
          search: "cinematic short film",
          description: "An architect's obsession with perfection threatens everything she loves.",
          tags: ["drama", "short film", "award winner"]
        },
        %{
          title: "The Undercurrent",
          search: "thriller suspense",
          description: "Beneath the surface of a quiet coastal town, secrets run deep.",
          tags: ["thriller", "mystery", "suspense"]
        },
        %{
          title: "Bright Side",
          search: "comedy sketch",
          description:
            "An eternal optimist faces the worst day of their life — and finds the bright side.",
          tags: ["comedy", "feel good"]
        },
        %{
          title: "Rogue Element",
          search: "action scene",
          description: "A disgraced agent goes off-grid to expose a conspiracy.",
          tags: ["action", "thriller", "espionage"]
        },
        %{
          title: "Silent Run",
          search: "thriller suspense",
          description: "A submarine crew faces an impossible choice in hostile waters.",
          tags: ["thriller", "military", "suspense"]
        },
        %{
          title: "End of the Line",
          search: "dramatic scene",
          description: "The last train out of town carries passengers with nowhere left to go.",
          tags: ["drama", "indie"]
        },
        %{
          title: "Golden Hour",
          search: "cinematic short film",
          description: "A photographer chases the perfect shot as time runs out.",
          tags: ["short film", "drama", "new"]
        }
      ],
      series_defs: [
        %{
          key: :the_bureau,
          title: "The Bureau",
          description:
            "Power, politics, and paperwork — a workplace drama where the stakes are always personal.",
          seasons: [
            %{
              title: "Season 1",
              search: "office business corporate",
              episode_count: 6,
              episode_titles: [
                "Pilot",
                "The Audit",
                "Chain of Command",
                "Whistleblower",
                "The Vote",
                "Restructuring"
              ]
            },
            %{
              title: "Season 2",
              search: "office business corporate",
              episode_count: 6,
              episode_titles: [
                "New Management",
                "The Merger",
                "Loyalty Test",
                "Closed Doors",
                "The Leak",
                "Annual Review"
              ]
            },
            %{
              title: "Season 3",
              search: "office business corporate",
              episode_count: 6,
              episode_titles: [
                "Fresh Start",
                "Old Guard",
                "Power Play",
                "The Resignation",
                "Crisis Mode",
                "Series Finale"
              ]
            }
          ]
        },
        %{
          key: :waypoint,
          title: "Waypoint",
          description: "A sci-fi adventure following a crew navigating uncharted space.",
          seasons: [
            %{
              title: "Season 1",
              search: "futuristic cityscape technology space",
              episode_count: 8,
              episode_titles: [
                "Signal Lost",
                "New Coordinates",
                "The Drift",
                "First Contact",
                "Gravity Well",
                "Dark Matter",
                "Course Correction",
                "Event Horizon"
              ]
            },
            %{
              title: "Season 2",
              search: "futuristic cityscape technology space",
              episode_count: 8,
              episode_titles: [
                "Reentry",
                "Station 7",
                "The Anomaly",
                "Split Decision",
                "Void Walker",
                "Binary Star",
                "Convergence",
                "Final Transmission"
              ]
            }
          ]
        },
        %{
          key: :kitchen_confidential,
          title: "Kitchen Confidential",
          description: "Heat, pressure, and passion — behind the scenes of competitive cooking.",
          new_season: true,
          seasons: [
            %{
              title: "Season 1",
              search: "cooking restaurant chef kitchen",
              episode_count: 5,
              episode_titles: [
                "Mise en Place",
                "The Rush",
                "Farm to Table",
                "Blind Taste",
                "Grand Finale"
              ]
            },
            %{
              title: "Season 2",
              search: "cooking restaurant chef kitchen",
              episode_count: 6,
              episode_titles: [
                "All Stars Return",
                "Mystery Box",
                "Street Food Challenge",
                "Pastry Week",
                "The Critics",
                "Champion's Table"
              ]
            }
          ]
        },
        %{
          key: :after_dark,
          title: "After Dark",
          description: "A limited thriller series — four nights, four stories, one city.",
          seasons: [
            %{
              title: "Season 1",
              search: "dark night city noir",
              episode_count: 4,
              episode_titles: ["The Call", "Watched", "Cornered", "Blackout"]
            }
          ]
        }
      ],
      collections: [
        %{key: :new_releases, title: "New Releases", items: [{:standalones, :recent, 5}]},
        %{
          key: :action_thriller,
          title: "Action & Thriller",
          items: [{:standalones, [3, 4, 6, 9, 12, 11]}]
        },
        %{
          key: :binge_worthy,
          title: "Binge-Worthy Series",
          items: [
            {:series, :the_bureau},
            {:series, :waypoint},
            {:series, :kitchen_confidential},
            {:series, :after_dark}
          ]
        },
        %{
          key: :staff_picks,
          title: "Staff Picks",
          items: [
            {:standalones, [0, 8, 14]},
            {:season, :waypoint, 0},
            {:season, :kitchen_confidential, 1}
          ]
        }
      ],
      plans: [
        %{
          name: "Monthly",
          amount: 1099,
          interval: :monthly,
          trial_days: 7,
          description: "Unlimited movies and shows."
        },
        %{
          name: "Annual",
          amount: 9999,
          interval: :yearly,
          trial_days: 7,
          description: "Save 24% with annual billing."
        },
        %{
          name: "Premium Monthly",
          amount: 1599,
          interval: :monthly,
          description: "Everything in Monthly plus premium features.",
          features: ["4K HDR", "Watch on 4 screens", "Offline downloads"]
        }
      ],
      coupons: [
        %{
          code: "WELCOME30",
          percent_off: 30,
          duration: :repeating,
          duration_in_months: 3,
          name: "30% off first 3 months"
        }
      ],
      landing_sections: [
        %{
          type: :hero_image,
          config: %{
            headline: "Thousands of Hours of Movies and Shows",
            subheadline: "Stream anytime, anywhere."
          }
        },
        %{
          type: :marketing_copy,
          config: %{
            headline: "Entertainment Without Limits",
            body:
              "From edge-of-your-seat thrillers to binge-worthy series, Prism+ has something for everyone."
          }
        },
        %{
          type: :content_row,
          config: %{
            source_type: "collection",
            collection_key: :new_releases,
            title: "New Releases"
          }
        },
        %{
          type: :content_row,
          config: %{
            source_type: "collection",
            collection_key: :binge_worthy,
            title: "Binge-Worthy Series"
          }
        },
        %{type: :plan_display, config: %{}},
        %{
          type: :faq,
          config: %{
            items: [
              %{
                question: "What devices can I watch on?",
                answer: "Prism+ works on web, iOS, Android, smart TVs, and streaming devices."
              },
              %{
                question: "Can I share my account?",
                answer: "Premium plans support up to 4 simultaneous screens."
              },
              %{
                question: "Is there a free trial?",
                answer: "Yes — all plans include a 7-day free trial. Cancel anytime."
              }
            ]
          }
        }
      ],
      hero_slides: [
        %{
          video_index: 0,
          headline: "The Last Signal",
          subheadline: "A signal from nowhere changes everything."
        },
        %{
          video_index: 4,
          headline: "The Getaway",
          subheadline: "The heist is just the beginning."
        },
        %{video_index: 1, headline: "Neon District", description: "Now Streaming"},
        %{video_index: 8, headline: "Glass City", subheadline: "Obsession has a price."}
      ],
      catalog_rows: [
        %{title: "Continue Watching", source_type: :continue_watching},
        %{title: "New Releases", source_type: :recent},
        %{title: "Action & Thriller", source_type: :collection, collection_key: :action_thriller},
        %{title: "Binge-Worthy Series", source_type: :collection, collection_key: :binge_worthy},
        %{title: "Kitchen Confidential", source_type: :new_seasons},
        %{title: "Staff Picks", source_type: :collection, collection_key: :staff_picks}
      ]
    }
  end
end
