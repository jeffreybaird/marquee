defmodule Marquee.DemoShorts do
  @moduledoc "Offline provisioning of reviewed, shared portrait footage for demo tenants."

  import Ecto.Query
  require Marquee.Otel

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.AdminDemo.ProtectedAsset
  alias Marquee.Audit
  alias Marquee.Content.{ShortFeed, ShortFeedItem, Video}
  alias Marquee.Events
  alias Marquee.Repo

  @fields ~w(slug title description mux_asset_id mux_playback_id duration aspect_ratio source_url creator_name creator_url license_url)a

  @doc "Seeds reviewed portrait media without provider calls. Exempt from doctests: database and filesystem access."
  def seed_catalog(org, theme) when theme in [:travel, :workshop] do
    with {:ok, clips} <- load_clips(theme),
         true <- valid_clips?(clips) do
      Marquee.Otel.with_span "marquee.demo_shorts.seed_catalog", %{"marquee.org.id" => org.id} do
        Repo.transaction(fn ->
          org = Repo.one!(from o in Organization, where: o.id == ^org.id, lock: "FOR UPDATE")
          videos = Enum.map(clips, &find_or_insert_video(org, &1))
          {:ok, updated} = seed(org, videos)
          %{organization: updated, videos: videos}
        end)
      end
    else
      _ -> {:error, :media_not_configured}
    end
  end

  @doc "Initializes a demo feed once, preserving subsequent operator edits. Exempt from doctests: database access."
  def seed(%Organization{id: org_id}, videos) when is_list(videos) do
    Marquee.Otel.with_span "marquee.demo_shorts.seed", %{"marquee.org.id" => org_id} do
      Repo.transaction(fn ->
        org = Repo.one!(from o in Organization, where: o.id == ^org_id, lock: "FOR UPDATE")
        ids = Enum.map(videos, & &1.id)

        eligible = fetch_eligible_videos(org_id, ids) |> Map.new(&{&1.id, &1})

        selected = ids |> Enum.uniq() |> Enum.filter(&Map.has_key?(eligible, &1))

        if org.features["demo_shorts_seeded"] || selected == [] do
          org
        else
          initialize_feed(org, selected)
        end
      end)
    end
  end

  defp fetch_eligible_videos(org_id, ids) do
    Video
    |> where([v], v.organization_id == ^org_id and v.id in ^ids)
    |> where([v], v.aspect_ratio == "9:16" and v.duration > 0.0 and v.duration <= 180.0)
    |> where([v], is_nil(v.deleted_at) and v.mux_status == "ready")
    |> where([v], not is_nil(v.mux_playback_id) and v.mux_playback_id not in ["", "pending"])
    |> Repo.all()
  end

  defp initialize_feed(org, ids) do
    position =
      Repo.one(
        from i in ShortFeedItem, where: i.organization_id == ^org.id, select: max(i.position)
      ) || 0

    ids
    |> Enum.with_index(position + 1)
    |> Enum.each(fn {id, position} ->
      Repo.insert!(%ShortFeedItem{organization_id: org.id, video_id: id, position: position},
        on_conflict: :nothing,
        conflict_target: [:organization_id, :video_id]
      )
    end)

    updated =
      org
      |> Ecto.Changeset.change(
        shorts_feed_enabled: true,
        shorts_feed_access: "subscribers_only",
        features:
          Map.merge(org.features || %{}, %{
            "demo_shorts_seeded" => true,
            "demo_shorts_video_ids" => ids
          })
      )
      |> Repo.update!()

    scope = %Scope{organization: updated}
    Events.broadcast(scope, {:short_feed_settings_updated, updated})
    Audit.log(scope, "short_feed.demo_seeded", updated, %{video_ids: ids})
    ShortFeed.invalidate_short_feed_cache(org.id)
    updated
  end

  defp load_clips(theme) do
    case Application.fetch_env(:marquee, :demo_shorts_catalog) do
      {:ok, catalog} when is_map(catalog) ->
        normalize_clips(Map.get(catalog, theme, Map.get(catalog, to_string(theme))))

      {:ok, _} ->
        {:error, :media_not_configured}

      :error ->
        with {:ok, bytes} <-
               File.read(Application.app_dir(:marquee, "priv/demo_shorts/catalog.json")),
             {:ok, catalog} when is_map(catalog) <- Jason.decode(bytes) do
          normalize_clips(catalog[to_string(theme)])
        end
    end
  end

  defp normalize_clips(clips) when is_list(clips) do
    if Enum.all?(clips, &is_map/1) do
      {:ok,
       Enum.map(clips, fn clip ->
         Map.new(@fields, &{&1, Map.get(clip, &1, Map.get(clip, to_string(&1)))})
       end)}
    else
      {:error, :media_not_configured}
    end
  end

  defp normalize_clips(_), do: {:error, :media_not_configured}

  defp valid_clips?(clips) do
    clips != [] and length(clips) <= 24 and
      Enum.all?(clips, fn clip ->
        Enum.all?(
          @fields -- [:duration],
          &(is_binary(clip[&1]) and clip[&1] not in ["", "pending"])
        ) and
          clip.aspect_ratio == "9:16" and is_number(clip.duration) and clip.duration > 0 and
          clip.duration <= 180
      end) and length(Enum.uniq_by(clips, & &1.slug)) == length(clips)
  end

  defp find_or_insert_video(org, clip) do
    Repo.insert!(
      %ProtectedAsset{
        mux_asset_id: clip.mux_asset_id,
        mux_playback_id: clip.mux_playback_id,
        template_version: "demo-shorts-v1"
      },
      on_conflict: :nothing,
      conflict_target: :mux_asset_id
    )

    Repo.get_by(Video, organization_id: org.id, slug: clip.slug) || insert_video(org, clip)
  end

  defp insert_video(org, clip) do
    description =
      "#{clip.description}\n\nFootage: #{clip.creator_name} on Pexels. Source: #{clip.source_url}\nCreator: #{clip.creator_url}\nLicense: #{clip.license_url}"

    video =
      %Video{organization_id: org.id, aspect_ratio: clip.aspect_ratio}
      |> Video.changeset(%{
        slug: clip.slug,
        title: clip.title,
        description: description,
        duration: clip.duration,
        mux_playback_id: clip.mux_playback_id,
        mux_status: "ready",
        published: true,
        visibility: "subscribers_only"
      })
      |> Repo.insert!()

    Events.broadcast(%Scope{organization: org}, {:video_created, video})
    video
  end
end
