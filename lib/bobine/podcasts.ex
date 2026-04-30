defmodule Bobine.Podcasts do
  @moduledoc """
  The Podcasts context.

  Public API for premium podcast shows, episodes, feed tokens, and the audio
  request log. Composes `Bobine.Podcasts.AccessControl` for subscriber access
  checks and wraps the Mux client + remote feed pipeline behind tagged
  tuples.

  Operates under the same architectural rules as the rest of the platform:
  organization-scoped reads/writes, soft deletes on user-facing content,
  paginated list helpers, structured errors, OpenTelemetry spans on every
  mutation, audit logging on operator-driven changes, and event broadcasts
  for downstream subscribers.
  """

  import Ecto.Query, warn: false

  require Logger
  require Bobine.Otel

  alias Bobine.Accounts.Organization
  alias Bobine.Audit
  alias Bobine.Billing
  alias Bobine.Events
  alias Bobine.Pagination
  alias Bobine.Repo
  alias Bobine.Viewers.Viewer

  alias Bobine.Podcasts.{
    AccessControl,
    AudioRequest,
    Episode,
    FeedToken,
    Show,
    ShowTier
  }

  ## ----------------------------------------------------------------------
  ## Show queries
  ## ----------------------------------------------------------------------

  @doc """
  Paginated list of shows for an organization, excluding soft-deleted.

  Exempt from doctest — hits the database.
  """
  def list_shows(%Organization{id: org_id}, opts \\ []) do
    published = Keyword.get(opts, :published)

    Show
    |> where(organization_id: ^org_id)
    |> where([s], is_nil(s.deleted_at))
    |> then(fn q ->
      if published != nil, do: where(q, [s], s.published == ^published), else: q
    end)
    |> order_by(asc: :title)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a show by id within an organization.

  Returns `{:ok, show}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_show(%Organization{id: org_id}, id) do
    Show
    |> where(organization_id: ^org_id, id: ^id)
    |> where([s], is_nil(s.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      show -> {:ok, show}
    end
  end

  @doc """
  Gets a show by its slug within an organization.

  Exempt from doctest — hits the database.
  """
  def get_show_by_slug(%Organization{id: org_id}, slug) do
    Show
    |> where(organization_id: ^org_id, slug: ^slug)
    |> where([s], is_nil(s.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      show -> {:ok, show}
    end
  end

  @doc """
  Preloads access plans (the show_tiers join's plans) on a show.

  Exempt from doctest — hits the database.
  """
  def with_access_plans(%Show{} = show), do: Repo.preload(show, [:access_plans, :show_tiers])

  ## ----------------------------------------------------------------------
  ## Show mutations
  ## ----------------------------------------------------------------------

  @doc """
  Creates a show. `attrs` may include a `:tier_plan_ids` list when
  `access_mode == "specific_tiers"`; the join records are inserted in the
  same transaction.

  Exempt from doctest — hits the database.
  """
  def create_show(scope, attrs) do
    Bobine.Otel.with_span "bobine.podcasts.create_show" do
      org_id = scope.organization.id
      attrs = Map.put(stringify_keys(attrs), "organization_id", org_id)
      tier_plan_ids = List.wrap(Map.get(attrs, "tier_plan_ids", []))

      Repo.transaction(fn ->
        with {:ok, show} <-
               %Show{} |> Show.changeset(Map.delete(attrs, "tier_plan_ids")) |> Repo.insert(),
             :ok <- replace_show_tiers(show, tier_plan_ids) do
          show |> Repo.preload([:show_tiers, :access_plans])
        else
          {:error, changeset} -> Repo.rollback({:error, :validation, changeset})
          {:error, _, _} = err -> Repo.rollback(err)
        end
      end)
      |> case do
        {:ok, %Show{} = show} ->
          Events.broadcast(scope, {:podcast_show_created, show})
          Audit.log(scope, "podcast_show.created", show)
          {:ok, show}

        {:error, reason} ->
          reason
      end
    end
  end

  @doc """
  Updates a show. Pass `:tier_plan_ids` to replace the access plan set.

  Exempt from doctest — hits the database.
  """
  def update_show(scope, %Show{} = show, attrs) do
    Bobine.Otel.with_span "bobine.podcasts.update_show" do
      attrs = stringify_keys(attrs)
      tier_change? = Map.has_key?(attrs, "tier_plan_ids")
      tier_plan_ids = List.wrap(Map.get(attrs, "tier_plan_ids", []))
      attrs = Map.delete(attrs, "tier_plan_ids")

      Repo.transaction(fn ->
        with {:ok, updated} <- show |> Show.changeset(attrs) |> Repo.update(),
             :ok <- maybe_replace_show_tiers(updated, tier_change?, tier_plan_ids) do
          Repo.preload(updated, [:show_tiers, :access_plans], force: true)
        else
          {:error, %Ecto.Changeset{} = cs} -> Repo.rollback({:error, :validation, cs})
          {:error, _, _} = err -> Repo.rollback(err)
        end
      end)
      |> case do
        {:ok, %Show{} = updated} ->
          Events.broadcast(scope, {:podcast_show_updated, updated})

          if tier_change? or Map.has_key?(attrs, "access_mode") or
               Map.has_key?(attrs, "audio_only_plan_id") do
            Events.broadcast(scope, {:podcast_show_access_changed, updated})
          end

          Audit.log(scope, "podcast_show.updated", updated, attrs)
          {:ok, updated}

        {:error, reason} ->
          reason
      end
    end
  end

  @doc """
  Soft-deletes a show. Episodes remain queryable via `including_deleted`
  variants but are filtered from default lists. Active feed tokens are
  revoked.

  Exempt from doctest — hits the database.
  """
  def soft_delete_show(scope, %Show{} = show) do
    Bobine.Otel.with_span "bobine.podcasts.soft_delete_show" do
      Repo.transaction(fn ->
        case show |> Show.soft_delete_changeset() |> Repo.update() do
          {:ok, deleted} ->
            revoke_all_active_tokens_for_show(deleted, "show_deleted")
            deleted

          {:error, cs} ->
            Repo.rollback({:error, :validation, cs})
        end
      end)
      |> case do
        {:ok, deleted} ->
          Events.broadcast(scope, {:podcast_show_deleted, deleted})
          Audit.log(scope, "podcast_show.deleted", deleted)
          {:ok, deleted}

        {:error, reason} ->
          reason
      end
    end
  end

  defp replace_show_tiers(%Show{id: show_id, organization_id: org_id}, plan_ids) do
    from(t in ShowTier, where: t.show_id == ^show_id) |> Repo.delete_all()

    Enum.reduce_while(plan_ids, :ok, fn plan_id, :ok ->
      attrs = %{organization_id: org_id, show_id: show_id, plan_id: plan_id}

      case %ShowTier{} |> ShowTier.changeset(attrs) |> Repo.insert() do
        {:ok, _} -> {:cont, :ok}
        {:error, cs} -> {:halt, {:error, :validation, cs}}
      end
    end)
  end

  defp maybe_replace_show_tiers(_, false, _), do: :ok
  defp maybe_replace_show_tiers(show, true, plan_ids), do: replace_show_tiers(show, plan_ids)

  ## ----------------------------------------------------------------------
  ## Audio upload (direct_upload shows)
  ## ----------------------------------------------------------------------

  @doc """
  Creates a Mux audio direct-upload URL and a draft episode in
  `mux_status: "waiting"`. Only valid for shows with
  `source_type: "direct_upload"`.

  Returns `{:ok, %{episode: episode, upload_url: url}}` or an error tuple.

  Exempt from doctest — calls Mux.
  """
  def create_audio_upload_url(scope, %Show{source_type: "direct_upload"} = show, attrs) do
    Bobine.Otel.with_span "bobine.podcasts.create_audio_upload_url",
                          %{"bobine.org.id" => show.organization_id} do
      title = Map.get(stringify_keys(attrs), "title") || "Untitled episode"
      origin = Map.get(stringify_keys(attrs), "current_origin")
      upload_params = build_audio_upload_params(show, origin)

      with {:ok, upload} <- mux_client().create_audio_direct_upload(upload_params),
           {:ok, episode} <- insert_draft_episode(scope, show, title, upload) do
        Events.broadcast(scope, {:podcast_episode_upload_initiated, episode})
        Audit.log(scope, "podcast_episode.upload_initiated", episode)
        {:ok, %{episode: episode, upload_url: upload_url_from(upload)}}
      end
    end
  end

  def create_audio_upload_url(_scope, %Show{source_type: source}, _attrs),
    do: {:error, :unsupported_source, source}

  defp insert_draft_episode(_scope, %Show{} = show, title, upload) do
    attrs = %{
      organization_id: show.organization_id,
      show_id: show.id,
      title: title,
      guid: "ep-#{Ecto.UUID.generate()}",
      mux_upload_id: upload_id_from(upload),
      mux_status: "waiting",
      status: "processing"
    }

    case %Episode{} |> Episode.changeset(attrs) |> Repo.insert() do
      {:ok, episode} -> {:ok, episode}
      {:error, cs} -> {:error, :validation, cs}
    end
  end

  defp build_audio_upload_params(_show, origin) do
    %{
      cors_origin: origin || "*",
      new_asset_settings: %{
        playback_policy: ["public"],
        mp3_support: "audio-only"
      }
    }
  end

  defp upload_url_from(%{"url" => url}), do: url
  defp upload_url_from(%{url: url}), do: url
  defp upload_url_from(other), do: Map.get(other, "url") || Map.get(other, :url)

  defp upload_id_from(%{"id" => id}), do: id
  defp upload_id_from(%{id: id}), do: id
  defp upload_id_from(other), do: Map.get(other, "id") || Map.get(other, :id)

  ## ----------------------------------------------------------------------
  ## Mux webhook hooks (called by MuxWebhookProcessor)
  ## ----------------------------------------------------------------------

  @doc """
  Looks up an episode by Mux upload id. Used by the Mux webhook
  `video.upload.asset_created` to attach an asset to the draft episode.

  Exempt from doctest — hits the database.
  """
  def link_audio_upload_to_asset(mux_upload_id, mux_asset_id) do
    Bobine.Otel.with_span "bobine.podcasts.link_audio_upload_to_asset" do
      case Repo.get_by(Episode, mux_upload_id: mux_upload_id) do
        nil ->
          {:error, :not_found}

        episode ->
          episode
          |> Episode.mux_status_changeset(%{
            mux_asset_id: mux_asset_id,
            mux_status: "preparing"
          })
          |> Repo.update()
          |> case do
            {:ok, ep} -> {:ok, ep}
            {:error, cs} -> {:error, :validation, cs}
          end
      end
    end
  end

  @doc """
  Marks an audio episode ready from a `video.asset.ready` Mux webhook.
  Returns `{:error, :not_found}` when no podcast episode owns the asset
  so the caller can fall through to the video pipeline.

  Exempt from doctest — hits the database.
  """
  def mark_episode_ready(mux_asset_id, metadata) do
    Bobine.Otel.with_span "bobine.podcasts.mark_episode_ready" do
      case Repo.get_by(Episode, mux_asset_id: mux_asset_id) do
        nil ->
          {:error, :not_found}

        episode ->
          attrs = %{
            mux_status: "ready",
            mux_playback_id: metadata[:playback_id],
            duration_seconds: trunc(metadata[:duration] || 0),
            mp3_byte_size: metadata[:mp3_byte_size],
            status: "published"
          }

          case episode |> Episode.mux_status_changeset(attrs) |> Repo.update() do
            {:ok, ep} ->
              org = Repo.get!(Organization, ep.organization_id)
              Events.broadcast(%{organization: org}, {:podcast_episode_ready, ep})
              {:ok, ep}

            {:error, cs} ->
              {:error, :validation, cs}
          end
      end
    end
  end

  @doc """
  Marks an audio episode errored from a `video.asset.errored` Mux webhook.
  Returns `{:error, :not_found}` when no podcast episode owns the asset.

  Exempt from doctest — hits the database.
  """
  def mark_episode_errored(mux_asset_id, error_details) do
    Bobine.Otel.with_span "bobine.podcasts.mark_episode_errored" do
      case Repo.get_by(Episode, mux_asset_id: mux_asset_id) do
        nil ->
          {:error, :not_found}

        episode ->
          attrs = %{
            mux_status: "errored",
            status: "errored",
            error_message: format_mux_error(error_details)
          }

          case episode |> Episode.mux_status_changeset(attrs) |> Repo.update() do
            {:ok, ep} ->
              org = Repo.get!(Organization, ep.organization_id)
              Events.broadcast(%{organization: org}, {:podcast_episode_errored, ep})
              {:ok, ep}

            {:error, cs} ->
              {:error, :validation, cs}
          end
      end
    end
  end

  defp format_mux_error(nil), do: nil

  defp format_mux_error(%{message: messages}) when is_list(messages),
    do: Enum.join(messages, "; ")

  defp format_mux_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_mux_error(other), do: inspect(other)

  ## ----------------------------------------------------------------------
  ## Episode queries
  ## ----------------------------------------------------------------------

  @doc """
  Paginated episodes for a show, excluding soft-deleted. Newest first.

  Exempt from doctest — hits the database.
  """
  def list_episodes(%Show{id: show_id}, opts \\ []) do
    Episode
    |> where(show_id: ^show_id)
    |> where([e], is_nil(e.deleted_at))
    |> order_by(desc: :publish_date, desc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Episodes visible to subscribers (published, not withdrawn, ready audio).

  Exempt from doctest — hits the database.
  """
  def list_published_episodes(%Show{id: show_id}) do
    Episode
    |> where(show_id: ^show_id)
    |> where([e], is_nil(e.deleted_at))
    |> where([e], is_nil(e.withdrawn_at))
    |> where([e], e.status == "published")
    |> order_by(desc: :publish_date, desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single episode within an organization.

  Exempt from doctest — hits the database.
  """
  def get_episode(%Organization{id: org_id}, id) do
    Episode
    |> where(organization_id: ^org_id, id: ^id)
    |> where([e], is_nil(e.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      ep -> {:ok, ep}
    end
  end

  ## ----------------------------------------------------------------------
  ## Episode mutations
  ## ----------------------------------------------------------------------

  @doc """
  Locks the listed override fields on an episode so feed sync no longer
  overwrites them.

  Exempt from doctest — hits the database.
  """
  def lock_episode_overrides(scope, %Episode{} = episode, locked_fields)
      when is_list(locked_fields) do
    Bobine.Otel.with_span "bobine.podcasts.lock_episode_overrides" do
      case episode |> Episode.lock_overrides_changeset(locked_fields) |> Repo.update() do
        {:ok, ep} ->
          Events.broadcast(scope, {:podcast_episode_overrides_locked, ep})
          Audit.log(scope, "podcast_episode.overrides_locked", ep, %{fields: locked_fields})
          {:ok, ep}

        {:error, cs} ->
          {:error, :validation, cs}
      end
    end
  end

  @doc """
  Withdraws an episode from subscriber feeds. Sets `status: "withdrawn"`
  and a `withdrawn_at` timestamp; the episode remains queryable for the
  operator.

  Exempt from doctest — hits the database.
  """
  def withdraw_episode(scope, %Episode{} = episode) do
    Bobine.Otel.with_span "bobine.podcasts.withdraw_episode" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changes = %{status: "withdrawn", withdrawn_at: now}

      case episode |> Episode.changeset(changes) |> Repo.update() do
        {:ok, ep} ->
          Events.broadcast(scope, {:podcast_episode_withdrawn, ep})
          Audit.log(scope, "podcast_episode.withdrawn", ep)
          {:ok, ep}

        {:error, cs} ->
          {:error, :validation, cs}
      end
    end
  end

  @doc """
  Upserts an episode parsed from a remote feed. Matches on
  (`show_id`, `guid`). When the episode already exists, fields listed in
  `episode.locked_fields` are preserved.

  Exempt from doctest — hits the database.
  """
  def upsert_episode_from_feed(%Show{} = show, parsed) when is_map(parsed) do
    guid = Map.get(parsed, :guid) || Map.get(parsed, "guid")

    if is_binary(guid) do
      case Repo.get_by(Episode, show_id: show.id, guid: guid) do
        nil -> insert_feed_episode(show, parsed)
        existing -> update_feed_episode(existing, parsed)
      end
    else
      {:error, :missing_guid}
    end
  end

  defp insert_feed_episode(show, parsed) do
    attrs =
      parsed
      |> Map.take([
        :guid,
        :title,
        :description,
        :episode_number,
        :season_number,
        :episode_type,
        :publish_date,
        :duration_seconds,
        :explicit,
        :remote_audio_url,
        :remote_audio_byte_size,
        :remote_audio_content_type
      ])
      |> Map.merge(%{
        organization_id: show.organization_id,
        show_id: show.id,
        status: "published"
      })

    %Episode{}
    |> Episode.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, ep} -> {:ok, ep}
      {:error, cs} -> {:error, :validation, cs}
    end
  end

  defp update_feed_episode(%Episode{locked_fields: locked} = episode, parsed) do
    locked_atoms = Enum.map(locked || [], &String.to_existing_atom/1)

    attrs =
      parsed
      |> Map.take([
        :title,
        :description,
        :episode_number,
        :season_number,
        :episode_type,
        :publish_date,
        :duration_seconds,
        :explicit,
        :remote_audio_url,
        :remote_audio_byte_size,
        :remote_audio_content_type
      ])
      |> Map.drop(locked_atoms)

    if attrs == %{} do
      {:ok, episode}
    else
      episode
      |> Episode.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, ep} -> {:ok, ep}
        {:error, cs} -> {:error, :validation, cs}
      end
    end
  end

  ## ----------------------------------------------------------------------
  ## Feed tokens
  ## ----------------------------------------------------------------------

  @doc """
  Issues a feed token for a (show, viewer) pair, reusing an existing
  active token rather than minting a duplicate.

  Exempt from doctest — hits the database.
  """
  def issue_feed_token(%Show{} = show, %Viewer{} = viewer) do
    Bobine.Otel.with_span "bobine.podcasts.issue_feed_token" do
      case existing_active_token(show.id, viewer.id) do
        nil ->
          attrs = %{
            organization_id: show.organization_id,
            show_id: show.id,
            viewer_id: viewer.id
          }

          case attrs |> FeedToken.new_changeset() |> Repo.insert() do
            {:ok, token} ->
              org = %{organization: %{id: show.organization_id}}
              Events.broadcast(org, {:podcast_feed_token_issued, token})
              {:ok, token}

            {:error, cs} ->
              {:error, :validation, cs}
          end

        existing ->
          {:ok, existing}
      end
    end
  end

  @doc """
  Revokes a feed token. Idempotent — revoking a revoked token is a no-op.

  Exempt from doctest — hits the database.
  """
  def revoke_feed_token(%FeedToken{status: "revoked"} = token, _reason), do: {:ok, token}

  def revoke_feed_token(%FeedToken{} = token, reason) when is_binary(reason) do
    Bobine.Otel.with_span "bobine.podcasts.revoke_feed_token" do
      case token |> FeedToken.revoke_changeset(reason) |> Repo.update() do
        {:ok, revoked} ->
          org = %{organization: %{id: revoked.organization_id}}
          Events.broadcast(org, {:podcast_feed_token_revoked, revoked})
          {:ok, revoked}

        {:error, cs} ->
          {:error, :validation, cs}
      end
    end
  end

  @doc """
  Issues a fresh token after revoking the existing active one, used by the
  subscriber's "regenerate feed URL" action.

  Exempt from doctest — hits the database.
  """
  def regenerate_feed_token(%Show{} = show, %Viewer{} = viewer) do
    Repo.transaction(fn ->
      revoke_existing_or_rollback(show.id, viewer.id)

      case issue_feed_token(show, viewer) do
        {:ok, token} -> token
        other -> Repo.rollback(other)
      end
    end)
  end

  defp revoke_existing_or_rollback(show_id, viewer_id) do
    case existing_active_token(show_id, viewer_id) do
      nil ->
        :ok

      existing ->
        case revoke_feed_token(existing, "regenerated") do
          {:ok, _} -> :ok
          other -> Repo.rollback(other)
        end
    end
  end

  @doc """
  Looks up a token by its public string. Returns `{:ok, token}` only when
  the token exists, is active, and is not expired.

  Exempt from doctest — hits the database.
  """
  def get_usable_feed_token(token) when is_binary(token) do
    case Repo.get_by(FeedToken, token: token) do
      nil -> {:error, :not_found}
      record -> if FeedToken.usable?(record), do: {:ok, record}, else: {:error, :revoked}
    end
  end

  @doc """
  Lists active tokens for a show. Used by the operator support view.

  Exempt from doctest — hits the database.
  """
  def list_active_tokens_for_show(%Show{id: show_id}) do
    FeedToken
    |> where(show_id: ^show_id, status: "active")
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  defp existing_active_token(show_id, viewer_id) do
    FeedToken
    |> where(show_id: ^show_id, viewer_id: ^viewer_id, status: "active")
    |> Repo.one()
  end

  defp revoke_all_active_tokens_for_show(%Show{id: show_id}, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(t in FeedToken, where: t.show_id == ^show_id and t.status == "active")
    |> Repo.update_all(
      set: [status: "revoked", revoked_at: now, revoked_reason: reason, updated_at: now]
    )

    :ok
  end

  ## ----------------------------------------------------------------------
  ## Token usage + audio request log
  ## ----------------------------------------------------------------------

  @doc """
  Records that a feed token was used. Idempotent across concurrent
  requests; only updates `last_used_at` and increments `request_count`.

  Exempt from doctest — hits the database.
  """
  def touch_feed_token(%FeedToken{id: id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(t in FeedToken, where: t.id == ^id)
    |> Repo.update_all(inc: [request_count: 1], set: [last_used_at: now, updated_at: now])

    :ok
  end

  @doc """
  Logs an audio/feed delivery request. Frequency is at most a few per
  subscriber-show pair per day (podcast clients poll on a multi-minute
  cadence and download each episode once), so the row is written direct
  rather than via a write buffer.

  Exempt from doctest — hits the database.
  """
  def log_audio_request(attrs) when is_map(attrs) do
    occurred_at = Map.get(attrs, :occurred_at) || DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = Map.put(attrs, :occurred_at, occurred_at)

    %AudioRequest{}
    |> AudioRequest.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, record}
      {:error, cs} -> {:error, :validation, cs}
    end
  end

  ## ----------------------------------------------------------------------
  ## Access
  ## ----------------------------------------------------------------------

  @doc """
  Convenience wrapper around `AccessControl.can_access?/3` that loads the
  viewer's active subscriptions and the show's access plans before
  delegating.

  Exempt from doctest — hits the database.
  """
  def can_access?(%Show{} = show, %Viewer{} = viewer) do
    show =
      case Map.get(show, :access_plans) do
        %Ecto.Association.NotLoaded{} -> Repo.preload(show, [:access_plans])
        nil -> Repo.preload(show, [:access_plans])
        _ -> show
      end

    org = %Organization{id: show.organization_id}

    subscriptions =
      case Billing.get_active_viewer_subscription(org, viewer) do
        {:ok, sub} -> [sub]
        {:error, :not_found} -> []
      end

    AccessControl.can_access?(show, viewer, subscriptions)
  end

  def can_access?(%Show{}, _), do: false

  @doc """
  Returns the published shows in the org that the viewer can access,
  paired with the viewer's active feed token (issuing one when none
  exists). Used by the subscriber account page.

  Exempt from doctest — hits the database.
  """
  def list_accessible_shows_for_viewer(%Organization{id: org_id}, %Viewer{} = viewer) do
    Show
    |> where(organization_id: ^org_id)
    |> where([s], is_nil(s.deleted_at) and s.published == true)
    |> order_by(asc: :title)
    |> Repo.all()
    |> Repo.preload([:access_plans, :show_tiers])
    |> Enum.filter(&can_access?(&1, viewer))
    |> Enum.map(&pair_with_token(&1, viewer))
    |> Enum.reject(fn {_show, token} -> is_nil(token) end)
  end

  defp pair_with_token(%Show{} = show, %Viewer{} = viewer) do
    case issue_feed_token(show, viewer) do
      {:ok, token} -> {show, token}
      _ -> {show, nil}
    end
  end

  ## ----------------------------------------------------------------------
  ## Analytics helpers
  ## ----------------------------------------------------------------------

  @doc """
  Counts audio requests for a show grouped by `request_type` over the
  given window.

  Exempt from doctest — hits the database.
  """
  def request_counts_for_show(%Show{id: show_id}, %DateTime{} = since) do
    from(r in AudioRequest,
      where: r.show_id == ^show_id and r.occurred_at >= ^since,
      group_by: r.request_type,
      select: {r.request_type, count(r.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Most recent audio requests for a show. Used by the operator support
  view to debug subscriber complaints.

  Exempt from doctest — hits the database.
  """
  def recent_requests_for_show(%Show{id: show_id}, limit \\ 50) do
    AudioRequest
    |> where(show_id: ^show_id)
    |> order_by(desc: :occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  ## ----------------------------------------------------------------------
  ## Helpers
  ## ----------------------------------------------------------------------

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp mux_client do
    Application.get_env(:bobine, :mux_client, Bobine.Content.MuxClient)
  end
end
