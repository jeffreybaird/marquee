defmodule Marquee.AdminDemo.Catalog do
  @moduledoc "Validated local travel template; cloning never contacts media providers."
  alias Marquee.Analytics.Snapshot
  alias Marquee.Branding.Theme
  alias Marquee.Catalog.{HeroSlide, Row, RowItem}
  alias Marquee.Content.{Collection, CollectionItem, Episode, Season, Series, Video}
  alias Marquee.Engagement.{Favorite, Progress, WatchHistory, WatchlistItem}
  alias Marquee.Podcasts.Show
  alias Marquee.Repo
  alias Marquee.Viewers.Viewer

  @doc "Reads and validates the configured local template. Performs filesystem access only."
  def load do
    config = Application.get_env(:marquee, :admin_demo, [])

    path =
      config[:catalog_path] ||
        Application.app_dir(:marquee, "priv/admin_demo/wanderlust_catalog.json")

    with {:ok, bytes} <- File.read(path),
         {:ok, %{"version" => version, "clips" => [_ | _] = clips}} <- Jason.decode(bytes),
         true <- (is_binary(version) or is_integer(version)) and Enum.all?(clips, &valid_clip?/1),
         true <- Enum.any?(clips, & &1["initial"]),
         true <- length(Enum.uniq_by(clips, & &1["slug"])) == length(clips) do
      {:ok, %{version: to_string(version), clips: clips}}
    else
      _ -> {:error, :demo_unavailable}
    end
  end

  defp valid_clip?(clip) when is_map(clip) do
    Enum.all?(
      ~w(slug title description source_url creator_name creator_url license_url collection mux_playback_id mux_asset_id),
      fn key ->
        is_binary(clip[key]) and clip[key] != ""
      end
    ) and is_number(clip["duration"]) and clip["duration"] > 0 and is_boolean(clip["initial"])
  end

  defp valid_clip?(_), do: false

  @doc "Clones a validated template inside the caller's tenant transaction. Requires database access."
  def seed(org, manifest) do
    videos = for clip <- manifest.clips, clip["initial"], do: {clip, insert_video(org, clip)}

    videos
    |> Enum.group_by(fn {clip, _} -> clip["collection"] end)
    |> Enum.with_index(1)
    |> Enum.each(fn {{title, entries}, index} -> seed_group(org, title, entries, index) end)

    hero =
      Repo.insert!(%Row{
        organization_id: org.id,
        title: "Explore somewhere new",
        source_type: :hero,
        visible: true,
        position: 0,
        filter_config: %{}
      })

    videos
    |> hero_order()
    |> Enum.take(3)
    |> Enum.with_index()
    |> Enum.each(fn {{_, video}, index} ->
      Repo.insert!(%HeroSlide{
        organization_id: org.id,
        row_id: hero.id,
        video_id: video.id,
        position: index,
        headline: video.title
      })
    end)

    %Theme{}
    |> Theme.changeset(%{
      organization_id: org.id,
      background: "#101918",
      surface: "#182623",
      text_primary: "#f7f5ef",
      text_secondary: "#b6c6bd",
      brand_primary: "#dba958",
      accent: "#dba958",
      font_heading: "Playfair Display",
      font_body: "Inter"
    })
    |> Repo.insert!()

    seed_members(org, videos)
    seed_shows(org)
    seed_analytics(org)
    :ok
  end

  defp hero_order(videos) do
    Enum.sort_by(videos, fn {clip, _} ->
      cond do
        String.contains?(clip["slug"], "bali") -> 0
        String.contains?(clip["slug"], "portugal") -> 1
        String.contains?(clip["slug"], "venice") -> 2
        true -> 3
      end
    end)
  end

  @doc "Copies one approved clip into a sandbox, retaining attribution and playback only. Requires database access."
  def insert_video(org, clip) do
    attribution =
      "#{clip["description"]}\n\nFootage: #{clip["creator_name"]} on Pexels. Source: #{clip["source_url"]}\nCreator: #{clip["creator_url"]}\nLicense: #{clip["license_url"]}"

    %Video{}
    |> Video.changeset(%{
      organization_id: org.id,
      slug: clip["slug"],
      title: clip["title"],
      description: attribution,
      duration: clip["duration"],
      mux_playback_id: clip["mux_playback_id"],
      mux_status: "ready",
      published: true,
      visibility: "subscribers_only"
    })
    |> Repo.insert!()
  end

  defp seed_group(org, title, entries, index) do
    collection =
      %Collection{organization_id: org.id}
      |> Collection.changeset(%{title: title, position: index})
      |> Repo.insert!()

    series =
      %Series{organization_id: org.id}
      |> Series.changeset(%{
        title: title,
        description: "Short journeys from the Wanderlust travel library.",
        position: index
      })
      |> Repo.insert!()

    season =
      %Season{organization_id: org.id, series_id: series.id}
      |> Season.changeset(%{title: "The first journey", season_number: 1})
      |> Repo.insert!()

    row =
      Repo.insert!(%Row{
        organization_id: org.id,
        title: title,
        source_type: :curated,
        position: index,
        visible: true,
        filter_config: %{}
      })

    entries
    |> Enum.with_index()
    |> Enum.each(fn {{_, video}, position} ->
      Repo.insert!(%CollectionItem{
        organization_id: org.id,
        collection_id: collection.id,
        video_id: video.id,
        item_type: :video,
        position: position
      })

      Repo.insert!(%Episode{
        organization_id: org.id,
        season_id: season.id,
        video_id: video.id,
        episode_number: position + 1
      })

      Repo.insert!(%RowItem{
        organization_id: org.id,
        row_id: row.id,
        video_id: video.id,
        position: position
      })
    end)

    Repo.update!(Ecto.Changeset.change(season, episode_count: length(entries)))
  end

  defp seed_analytics(org) do
    for offset <- 0..13,
        {metric, value} <- [
          {"daily_views", 120 + offset * 7},
          {"daily_watch_time", 2400 + offset * 90},
          {"daily_subscribers", 28 + offset},
          {"daily_revenue", 120 + offset * 3}
        ] do
      Repo.insert!(%Snapshot{
        organization_id: org.id,
        period_date: Date.add(Date.utc_today(), -offset),
        metric_type: metric,
        value: Decimal.new(value),
        metadata: %{"sample" => true, "label" => "Sample data"}
      })
    end
  end

  defp seed_members(org, videos) do
    profiles = [
      {"Alex Morgan", :active, "active"},
      {"Sam Rivera", :active, "trialing"},
      {"Jordan Lee", :active, "none"},
      {"Taylor Chen", :suspended, "active"},
      {"Casey Brooks", :banned, "none"},
      {"Riley Patel", :active, "canceled"}
    ]

    profiles
    |> Enum.with_index(1)
    |> Enum.each(fn {{name, status, subscription}, index} ->
      viewer =
        Repo.insert!(%Viewer{
          organization_id: org.id,
          display_name: name,
          email: "sample-#{index}@wanderlust.example.invalid",
          status: status,
          subscription_status: subscription,
          subscription_expires_at:
            if(subscription == "active",
              do: DateTime.add(DateTime.utc_now(), 30 * 86_400) |> DateTime.truncate(:second)
            ),
          trial_expires_at:
            if(subscription == "trialing",
              do: DateTime.add(DateTime.utc_now(), 7 * 86_400) |> DateTime.truncate(:second)
            ),
          confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          onboarding_completed: true,
          metadata: %{"admin_demo_sample" => true}
        })

      seed_member_activity(org, viewer, videos, index)
    end)
  end

  defp seed_member_activity(org, viewer, videos, index) do
    {_, video} = Enum.at(videos, rem(index - 1, length(videos)))
    duration = (video.duration || 60) * 1.0
    position = min(duration / 3, 30.0)

    Repo.insert!(%Progress{
      organization_id: org.id,
      viewer_id: viewer.id,
      video_id: video.id,
      position: position,
      duration: duration,
      completed: false
    })

    Repo.insert!(%WatchlistItem{
      organization_id: org.id,
      viewer_id: viewer.id,
      video_id: video.id,
      item_type: :video,
      position: 0
    })

    Repo.insert!(%Favorite{organization_id: org.id, viewer_id: viewer.id, video_id: video.id})

    Repo.insert!(%WatchHistory{
      organization_id: org.id,
      viewer_id: viewer.id,
      video_id: video.id,
      watched_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp seed_shows(org) do
    for {title, slug, description, published} <- [
          {"Wanderlust Field Notes", "wanderlust-field-notes",
           "Stories behind memorable journeys. Edit this sample show's details to plan your own series.",
           true},
          {"The Weekend Explorer", "weekend-explorer",
           "A sample show for short escapes and thoughtful travel. Audio publishing is unavailable in this demo.",
           false}
        ] do
      %Show{organization_id: org.id}
      |> Show.changeset(%{
        title: title,
        slug: slug,
        description: description,
        author: "Wanderlust TV",
        source_type: "direct_upload",
        access_mode: "any_active",
        published: published
      })
      |> Repo.insert!()
    end
  end
end
