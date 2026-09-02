defmodule Marquee.Onboarding.StarterContent do
  @moduledoc """
  Seeds a brand-new organization with sample/starter content so a fresh trial
  operator can immediately see what their platform looks like: a set of guide
  videos, a couple of sample collections, and a varied homepage (hero, curated
  "staff picks", collection-backed, and recently-added rows).

  Everything created here is flagged `is_sample: true`, which (a) exempts it
  from the trial's total-duration cap and (b) makes it removable in one click
  via `clear/1`.

  ## Placeholder media

  The sample videos point at Mux's public demo playback ID. They play out of
  the box so the operator can preview the viewer site, and are trivially
  swapped for real guide videos later by editing `@placeholder_playback_id`
  (and, optionally, per-spec `:playback_id`).

  All public functions hit the database and are therefore doctest-exempt.
  """

  import Ecto.Query

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.Catalog
  alias Marquee.Catalog.Row
  alias Marquee.Content
  alias Marquee.Content.{Collection, Video}
  alias Marquee.Repo

  # Mux's public demo asset — plays without any Mux account. Replace with real
  # guide-video playback IDs when they exist; sample specs may override this
  # per-video via a `:playback_id` key.
  @placeholder_playback_id "DS00Spx1CV902MCtPj5WknGlR102V5HFkDe"

  @collections [
    %{
      key: :guide,
      title: "Getting Started with Marquee",
      description: "Short guides that walk you through setting up your channel.",
      type: :series,
      videos: [
        %{
          title: "Welcome to Marquee",
          description: "A quick tour of your new platform.",
          duration: 92.0
        },
        %{
          title: "Uploading Your First Video",
          description: "How to add and publish video.",
          duration: 141.0
        },
        %{
          title: "Branding Your Channel",
          description: "Colors, fonts, and your logo.",
          duration: 118.0
        },
        %{
          title: "Publishing & Monetizing",
          description: "Plans, subscriptions, and going live.",
          duration: 167.0
        }
      ]
    },
    %{
      key: :series,
      title: "Sample Series: Behind the Lens",
      description: "An example multi-episode series to show off season layouts.",
      type: :series,
      videos: [
        %{title: "Behind the Lens — Episode 1", description: "Sample episode.", duration: 604.0},
        %{title: "Behind the Lens — Episode 2", description: "Sample episode.", duration: 588.0},
        %{title: "Behind the Lens — Episode 3", description: "Sample episode.", duration: 611.0}
      ]
    },
    %{
      key: :category,
      title: "Sample Shorts",
      description: "A category of short-form clips.",
      type: :category,
      videos: [
        %{title: "Short: City Lights", description: "Sample short.", duration: 47.0},
        %{title: "Short: Open Road", description: "Sample short.", duration: 53.0},
        %{title: "Short: Quiet Morning", description: "Sample short.", duration: 61.0}
      ]
    }
  ]

  @doc """
  Returns true if the organization already has seeded sample content.

  Exempt from doctest — hits the database.
  """
  def seeded?(%Organization{id: org_id}) do
    Repo.exists?(
      from(v in Video,
        where: v.organization_id == ^org_id and v.is_sample and is_nil(v.deleted_at)
      )
    )
  end

  @doc """
  Seeds sample videos, collections, and homepage rows for the organization.

  Accepts a `%Scope{}` or an `%Organization{}`. Idempotent: returns
  `{:ok, :already_seeded}` when sample content is already present. On success
  returns `{:ok, %{videos: n, collections: n, rows: n}}`. Runs in a single
  transaction so a partial failure leaves no half-seeded org.

  Exempt from doctest — hits the database.
  """
  def seed(target) do
    scope = to_scope(target)

    if seeded?(scope.organization) do
      {:ok, :already_seeded}
    else
      do_seed(scope)
    end
  end

  @doc """
  Soft-deletes all sample content (videos, collections, rows) for the org.

  Returns `{:ok, %{videos: n, collections: n, rows: n}}` with the number of
  records removed. Only sample content is touched; operator-created content is
  never affected.

  Exempt from doctest — hits the database.
  """
  def clear(target) do
    scope = to_scope(target)
    org_id = scope.organization.id
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      videos = soft_delete_samples(Video, org_id, now)
      collections = soft_delete_samples(Collection, org_id, now)
      rows = soft_delete_samples(Row, org_id, now)

      Marquee.Events.broadcast(scope, {:sample_content_cleared, scope.organization})
      %{videos: videos, collections: collections, rows: rows}
    end)
  end

  # -- seeding ---------------------------------------------------------------

  defp do_seed(scope) do
    Repo.transaction(fn ->
      collections = Enum.map(@collections, &seed_collection!(scope, &1))
      seed_rows!(scope, collections)

      %{
        videos: collections |> Enum.flat_map(& &1.videos) |> length(),
        collections: length(collections),
        rows: 6
      }
    end)
  end

  defp seed_collection!(scope, %{videos: video_specs} = spec) do
    {:ok, collection} =
      Content.create_collection(scope, %{
        title: spec.title,
        description: spec.description,
        type: spec.type,
        visible: true,
        is_sample: true
      })

    videos =
      video_specs
      |> Enum.with_index()
      |> Enum.map(fn {vspec, index} ->
        video = create_sample_video!(scope, vspec)
        {:ok, _item} = Content.add_video_to_collection(scope, collection, video, index)
        video
      end)

    %{key: spec.key, collection: collection, videos: videos}
  end

  defp create_sample_video!(scope, vspec) do
    playback_id = Map.get(vspec, :playback_id, @placeholder_playback_id)

    {:ok, video} =
      Content.create_video(scope, %{
        organization_id: scope.organization.id,
        title: vspec.title,
        slug: Content.slugify(vspec.title),
        description: vspec.description,
        duration: vspec.duration,
        mux_playback_id: playback_id,
        mux_status: "ready",
        published: true,
        visibility: "public",
        landscape_thumbnail_url: thumbnail_url(playback_id, :landscape),
        portrait_thumbnail_url: thumbnail_url(playback_id, :portrait),
        is_sample: true
      })

    video
  end

  defp seed_rows!(scope, collections) do
    by_key = Map.new(collections, &{&1.key, &1})
    guide = by_key[:guide]
    series = by_key[:series]
    all_videos = Enum.flat_map(collections, & &1.videos)

    seed_hero!(scope, Enum.take(guide.videos, 2))
    seed_curated_row!(scope, "Staff Picks", Enum.take(all_videos, 4), position: 1)
    seed_collection_row!(scope, guide.collection, position: 2)
    seed_collection_row!(scope, series.collection, position: 3)
    seed_recent_row!(scope, position: 4)
    :ok
  end

  defp seed_hero!(scope, videos) do
    {:ok, row} =
      Catalog.create_hero_row(scope, %{title: "Featured", is_sample: true, position: 0})

    videos
    |> Enum.with_index()
    |> Enum.each(fn {video, index} ->
      {:ok, _slide} =
        Catalog.create_hero_slide(scope, row, %{
          video_id: video.id,
          position: index,
          headline: video.title
        })
    end)

    row
  end

  defp seed_curated_row!(scope, title, videos, opts) do
    {:ok, row} =
      Catalog.create_row(scope, %{
        title: title,
        source_type: :curated,
        visible: true,
        is_sample: true,
        position: Keyword.fetch!(opts, :position)
      })

    videos
    |> Enum.with_index()
    |> Enum.each(fn {video, index} ->
      {:ok, _item} = Catalog.add_item_to_row(scope, row, video, index)
    end)

    row
  end

  defp seed_collection_row!(scope, %Collection{} = collection, opts) do
    {:ok, row} =
      Catalog.create_row(scope, %{
        title: collection.title,
        source_type: :collection,
        source_id: collection.id,
        visible: true,
        is_sample: true,
        position: Keyword.fetch!(opts, :position)
      })

    row
  end

  defp seed_recent_row!(scope, opts) do
    {:ok, row} =
      Catalog.create_row(scope, %{
        title: "Recently Added",
        source_type: :recent,
        visible: true,
        is_sample: true,
        position: Keyword.fetch!(opts, :position)
      })

    row
  end

  # -- helpers ---------------------------------------------------------------

  defp soft_delete_samples(schema, org_id, now) do
    {count, _} =
      schema
      |> where([r], r.organization_id == ^org_id and r.is_sample and is_nil(r.deleted_at))
      |> Repo.update_all(set: [deleted_at: now])

    count
  end

  defp thumbnail_url(playback_id, :landscape) do
    "https://image.mux.com/#{playback_id}/thumbnail.jpg?width=640&height=360&fit_mode=crop"
  end

  defp thumbnail_url(playback_id, :portrait) do
    "https://image.mux.com/#{playback_id}/thumbnail.jpg?width=480&height=720&fit_mode=crop"
  end

  defp to_scope(%Scope{} = scope), do: scope
  defp to_scope(%Organization{} = org), do: %Scope{organization: org}
end
