defmodule Marquee.SubscriberDemo.Catalog do
  @moduledoc "Provisions the reviewed Workshop media manifest into a small, repeatable catalog."
  import Ecto.Query
  require Marquee.Otel

  alias Marquee.Accounts.Scope
  alias Marquee.Catalog.{HeroSlide, Row}
  alias Marquee.Content
  alias Marquee.Content.{Collection, CollectionItem, Episode, Season, Series, Video}
  alias Marquee.Events
  alias Marquee.Repo
  alias Marquee.SubscriberDemo

  @manifest_fields [
    :slug,
    :title,
    :description,
    :mux_asset_id,
    :mux_playback_id,
    :duration,
    :source_url
  ]

  @doc "Seeds a configured manifest; refuses to publish unconfigured sample playback IDs."
  def seed(org) do
    manifest = load_manifest()

    cond do
      not SubscriberDemo.enabled?(org) ->
        {:error, :forbidden}

      not valid_manifest?(manifest) ->
        {:error, :media_not_configured}

      true ->
        Marquee.Otel.with_span "marquee.subscriber_demo.seed_catalog", %{
          "marquee.org.id" => org.id
        } do
          Repo.transaction(fn -> seed_manifest(org, manifest) end)
        end
    end
  end

  defp load_manifest do
    case Application.fetch_env(:marquee, :subscriber_demo_catalog) do
      {:ok, manifest} -> manifest
      :error -> load_manifest_file()
    end
  end

  defp load_manifest_file do
    path =
      Application.get_env(
        :marquee,
        :subscriber_demo_manifest_path,
        Application.app_dir(:marquee, "priv/subscriber_demo/workshop_catalog.json")
      )

    with {:ok, json} <- File.read(path),
         {:ok, entries} when is_list(entries) <- Jason.decode(json),
         true <- Enum.all?(entries, &is_map/1) do
      Enum.map(entries, fn entry ->
        Map.new(@manifest_fields, &{&1, Map.get(entry, Atom.to_string(&1))})
      end)
    else
      _ -> []
    end
  end

  defp valid_manifest?(manifest) when is_list(manifest) and length(manifest) in 3..24 do
    Enum.all?(manifest, fn item ->
      is_map(item) &&
        Enum.all?(
          [:slug, :title, :description, :mux_playback_id, :mux_asset_id, :source_url],
          fn key ->
            is_binary(item[key]) && item[key] not in ["", "pending"]
          end
        ) && is_number(item[:duration]) && item[:duration] > 0
    end) && length(Enum.uniq_by(manifest, & &1.slug)) == length(manifest)
  end

  defp valid_manifest?(_), do: false

  defp seed_manifest(org, manifest) do
    videos = Enum.map(manifest, &upsert_video(org, &1))
    first = hd(videos)

    series =
      upsert(Series, org, "inside-the-workshop", %{
        title: "Inside The Workshop",
        description:
          "A short series of observed creative work. Explore the episodes, save a favorite, and pick up where you left off.",
        cover_image_url: thumbnail(first),
        visible: true
      })

    season =
      (Repo.get_by(Season, organization_id: org.id, series_id: series.id, season_number: 1) ||
         %Season{organization_id: org.id, series_id: series.id})
      |> Season.changeset(%{
        title: "The creative process",
        season_number: 1,
        visible: true,
        cover_image_url: thumbnail(first)
      })
      |> Repo.insert_or_update!()

    Enum.with_index(videos, 1)
    |> Enum.each(fn {video, number} ->
      if !Repo.exists?(
           from e in Episode,
             where:
               e.organization_id == ^org.id and e.season_id == ^season.id and
                 e.video_id == ^video.id
         ) do
        {:ok, _} =
          Content.add_episode(%Scope{organization: org}, season, video, %{episode_number: number})
      end
    end)

    collections = seed_collections(org, videos)

    rows = seed_rows(org, series, videos, collections)

    org
    |> Ecto.Changeset.change(
      features:
        Map.merge(org.features || %{}, %{
          "subscriber_demo_video_ids" => Enum.map(videos, & &1.id),
          "subscriber_demo_series_slug" => series.slug,
          "subscriber_demo_row_ids" => Enum.map(rows, & &1.id)
        })
    )
    |> Repo.update!()

    Events.broadcast(%Scope{organization: org}, {:subscriber_demo_catalog_seeded, series})
    Marquee.Catalog.invalidate_hero_cache_for_org(org.id)
    Marquee.Cache.delete_by_prefix("row_content:#{org.id}:")
    Marquee.Cache.delete_by_prefix("row_content_videos:#{org.id}:")
    %{series: series, videos: videos, collections: collections}
  end

  defp upsert_video(org, item) do
    attrs =
      item |> Map.take([:slug, :title, :description, :mux_playback_id, :mux_asset_id, :duration])

    attrs =
      Map.merge(attrs, %{
        description: item.description <> "\n\nFootage source: " <> item.source_url,
        published: true,
        mux_status: "ready",
        visibility: "subscribers_only",
        landscape_thumbnail_url:
          "https://image.mux.com/#{item.mux_playback_id}/thumbnail.jpg?width=1280&height=720&fit_mode=smartcrop",
        portrait_thumbnail_url:
          "https://image.mux.com/#{item.mux_playback_id}/thumbnail.jpg?width=600&height=900&fit_mode=smartcrop"
      })

    upsert(Video, org, item.slug, attrs)
  end

  defp seed_collections(org, videos) do
    ["Start here", "Explore the process", "From the workbench"]
    |> Enum.with_index()
    |> Enum.map(fn {title, index} ->
      offset = div(length(videos) * index, 3)
      selected = Enum.take(Enum.drop(videos, offset) ++ Enum.take(videos, offset), 12)
      seed_collection(org, title, selected)
    end)
  end

  defp seed_collection(org, title, videos) do
    collection =
      upsert(Collection, org, Marquee.Slug.generate(title), %{
        title: title,
        description: "Selected episodes from Inside The Workshop.",
        cover_image_url: thumbnail(hd(videos)),
        visible: true
      })

    video_ids = Enum.map(videos, & &1.id)

    Repo.delete_all(
      from item in CollectionItem,
        where:
          item.organization_id == ^org.id and item.collection_id == ^collection.id and
            (is_nil(item.video_id) or item.video_id not in ^video_ids)
    )

    Enum.with_index(videos)
    |> Enum.each(fn {video, position} ->
      (Repo.get_by(CollectionItem,
         organization_id: org.id,
         collection_id: collection.id,
         video_id: video.id
       ) ||
         %CollectionItem{
           organization_id: org.id,
           collection_id: collection.id,
           video_id: video.id
         })
      |> CollectionItem.changeset(%{item_type: :video, position: position})
      |> Repo.insert_or_update!()
    end)

    collection
  end

  defp seed_rows(org, series, videos, collections) do
    retire_legacy_welcome_row(org)

    continued =
      upsert_row(org, "Continue Watching", %{source_type: :continue_watching, position: -9})

    hero = upsert_row(org, "Workshop demo feature", %{source_type: :hero, position: -11})

    Enum.each(0..2, fn position ->
      video = Enum.at(videos, div(length(videos) * position, 3))

      (Repo.get_by(HeroSlide, organization_id: org.id, row_id: hero.id, position: position) ||
         %HeroSlide{organization_id: org.id, row_id: hero.id})
      |> HeroSlide.changeset(%{
        video_id: video.id,
        position: position,
        headline: if(position == 0, do: series.title, else: video.title),
        subheadline: "A subscriber experience you can try",
        description: video.description,
        background_image_url: thumbnail(video),
        title_logo_url: nil,
        channel_logo_url: nil,
        brand_tag: "THE WORKSHOP",
        primary_cta_label: "Play episode",
        secondary_cta_label: "Explore series",
        show_headline: true,
        show_subheadline: true,
        show_description: true,
        show_brand_tag: true,
        show_primary_cta: true,
        show_secondary_cta: true
      })
      |> Repo.insert_or_update!()
    end)

    collection_rows =
      Enum.with_index(collections, -8)
      |> Enum.map(fn {collection, position} ->
        upsert_row(org, collection.title, %{
          source_type: :collection,
          source_id: collection.id,
          max_items: 12,
          position: position
        })
      end)

    [continued, hero | collection_rows]
  end

  defp retire_legacy_welcome_row(org) do
    managed_ids = (org.features || %{})["subscriber_demo_row_ids"] || []

    Repo.all(
      from row in Row,
        where:
          row.organization_id == ^org.id and row.id in ^managed_ids and
            row.title == "Your subscriber demo" and row.source_type == :welcome_text and
            is_nil(row.deleted_at)
    )
    |> Enum.each(fn row ->
      {:ok, _} = Marquee.Catalog.delete_row(%Scope{organization: org}, row)
    end)
  end

  defp upsert_row(org, title, %{source_type: :hero} = attrs) do
    (Repo.one(
       from row in Row,
         where:
           row.organization_id == ^org.id and row.source_type == :hero and is_nil(row.deleted_at)
     ) ||
       %Row{organization_id: org.id})
    |> Row.changeset(Map.merge(attrs, %{title: title, visible: true, max_items: 6}))
    |> Repo.insert_or_update!()
  end

  defp upsert_row(org, title, attrs) do
    (Repo.get_by(Row, organization_id: org.id, title: title) || %Row{organization_id: org.id})
    |> Row.changeset(
      Map.merge(attrs, %{title: title, visible: true, max_items: Map.get(attrs, :max_items, 6)})
    )
    |> Repo.insert_or_update!()
  end

  defp upsert(schema, org, slug, attrs) do
    record =
      Repo.get_by(schema, organization_id: org.id, slug: slug) ||
        struct(schema, organization_id: org.id)

    record |> schema.changeset(attrs) |> Repo.insert_or_update!()
  end

  defp thumbnail(video), do: video.landscape_thumbnail_url
end
