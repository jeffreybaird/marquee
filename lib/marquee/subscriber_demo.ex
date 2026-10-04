defmodule Marquee.SubscriberDemo do
  @moduledoc """
  Ephemeral subscriber identities for the explicitly enabled Workshop demo.

  Demo visitors use the normal viewer and engagement paths. Their synthetic
  identities and activity are erased after two hours; no email or billing
  identity is created. Catalog provisioning is an explicit operator task.
  """
  import Ecto.Query
  require Marquee.Otel

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.Buffers.ProgressBuffer
  alias Marquee.Content.Video
  alias Marquee.Engagement
  alias Marquee.Engagement.{Progress, WatchHistory}
  alias Marquee.Events
  alias Marquee.Repo
  alias Marquee.SubscriberDemo.Catalog
  alias Marquee.Viewers
  alias Marquee.Viewers.Viewer
  alias Marquee.Workers.SubscriberDemoCleanup

  @lifetime_seconds 7_200

  @doc """
  Checks whether this organization offers the subscriber demo.

      iex> Marquee.SubscriberDemo.enabled?(nil)
      false
  """
  def enabled?(%{slug: "the-workshop", features: %{"subscriber_demo" => true}}), do: true
  def enabled?(_), do: false

  @doc """
  Identifies a synthetic demo viewer.

      iex> Marquee.SubscriberDemo.demo_viewer?(nil)
      false
  """
  def demo_viewer?(%{metadata: %{"subscriber_demo" => true}}), do: true
  def demo_viewer?(_), do: false

  @doc """
  Checks demo expiration, failing closed for malformed expiration metadata.

      iex> Marquee.SubscriberDemo.expired?(nil)
      false
  """
  def expired?(viewer), do: expired_at?(viewer, DateTime.utc_now())

  @doc "Creates a private, subscribed demo identity and seeds its initial activity."
  def start_session(%Organization{} = org) do
    Marquee.Otel.with_span "marquee.subscriber_demo.start", %{"marquee.org.id" => org.id} do
      with true <- enabled?(org),
           [_ | _] = videos <- initial_videos(org) do
        Repo.transaction(fn -> create_session(org, videos) end)
      else
        false -> {:error, :forbidden}
        [] -> {:error, :demo_unavailable}
      end
    end
  end

  @doc "Seeds the curated catalog without contacting external services."
  def seed_catalog(org), do: Catalog.seed(org)

  @doc "Erases a bounded batch of expired demo identities and all their activity."
  def cleanup_expired(%Organization{} = org, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    cutoff = DateTime.to_iso8601(now)
    oldest = DateTime.add(now, -@lifetime_seconds)
    limit = opts |> Keyword.get(:per_page, 100) |> max(1) |> min(100)

    Marquee.Otel.with_span "marquee.subscriber_demo.cleanup", %{"marquee.org.id" => org.id} do
      Repo.transaction(fn ->
        Viewer
        |> where(organization_id: ^org.id)
        |> where([v], fragment("?->>'subscriber_demo' = 'true'", v.metadata))
        |> where(
          [v],
          fragment("?->>'subscriber_demo_expires_at' IS NULL", v.metadata) or
            v.inserted_at <= ^oldest or
            fragment("?->>'subscriber_demo_expires_at' <= ?", v.metadata, ^cutoff) or
            fragment(
              "?->>'subscriber_demo_expires_at' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'",
              v.metadata
            )
        )
        |> order_by(asc: :inserted_at, asc: :id)
        |> limit(^limit)
        |> lock("FOR UPDATE SKIP LOCKED")
        |> Repo.all()
        |> Enum.filter(&expired_at?(&1, now))
        |> tap(&Enum.each(&1, fn viewer -> erase_viewer(org, viewer) end))
        |> length()
      end)
      |> case do
        {:ok, count} -> {:ok, count}
        error -> error
      end
    end
  end

  defp expired_at?(%{metadata: %{"subscriber_demo" => true} = metadata}, now) do
    with expiry when is_binary(expiry) <- metadata["subscriber_demo_expires_at"],
         {:ok, expires_at, _} <- DateTime.from_iso8601(expiry) do
      DateTime.compare(expires_at, now) != :gt
    else
      _ -> true
    end
  end

  defp expired_at?(_, _), do: false

  defp initial_videos(org) do
    video_ids = (org.features || %{})["subscriber_demo_video_ids"]

    Video
    |> where(organization_id: ^org.id, published: true, mux_status: "ready")
    |> where([v], is_nil(v.deleted_at) and not is_nil(v.mux_playback_id))
    |> where([v], v.mux_playback_id not in ["", "pending"])
    |> restrict_demo_videos(video_ids)
    |> order_by(asc: :slug)
    |> limit(2)
    |> Repo.all()
  end

  defp restrict_demo_videos(query, ids) when is_list(ids), do: where(query, [v], v.id in ^ids)
  defp restrict_demo_videos(query, _), do: query

  defp create_session(org, videos) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, @lifetime_seconds)

    viewer =
      %Viewer{
        organization_id: org.id,
        email: "demo-#{Ecto.UUID.generate()}@subscriber.invalid",
        display_name: "Demo visitor",
        confirmed_at: now,
        subscription_status: "active",
        subscription_expires_at: expires_at,
        onboarding_completed: true,
        metadata: %{
          "subscriber_demo" => true,
          "subscriber_demo_expires_at" => DateTime.to_iso8601(expires_at)
        }
      }
      |> Repo.insert!()

    seed_activity(org, viewer, List.last(videos), now)

    %{organization_id: org.id}
    |> SubscriberDemoCleanup.new(scheduled_at: expires_at)
    |> Oban.insert!()

    Events.broadcast(%Scope{organization: org}, {:subscriber_demo_started, viewer})
    %{viewer: viewer, token: Viewers.generate_viewer_session_token(viewer)}
  end

  defp seed_activity(org, viewer, video, now) do
    Repo.insert!(%Progress{
      organization_id: org.id,
      viewer_id: viewer.id,
      video_id: video.id,
      position: min((video.duration || 120.0) / 4, 30.0),
      duration: video.duration,
      completed: false
    })

    Repo.insert!(%WatchHistory{
      organization_id: org.id,
      viewer_id: viewer.id,
      video_id: video.id,
      watched_at: now
    })
  end

  defp erase_viewer(org, viewer) do
    ProgressBuffer.list_viewer_entries(org.id, viewer.id)
    |> Enum.each(&ProgressBuffer.delete_viewer(org.id, viewer.id, &1.video_id))

    for schema <- [
          Progress,
          WatchHistory,
          Engagement.WatchlistItem,
          Engagement.Favorite,
          Engagement.QueueItem,
          Engagement.PlaybackDropOff,
          Marquee.Analytics.Event
        ] do
      Repo.delete_all(
        from row in schema, where: row.organization_id == ^org.id and row.viewer_id == ^viewer.id
      )
    end

    Repo.delete!(viewer)
    Events.broadcast(%Scope{organization: org}, {:subscriber_demo_expired, viewer})
  end
end
