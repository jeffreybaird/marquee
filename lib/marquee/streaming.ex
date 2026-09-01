defmodule Marquee.Streaming do
  @moduledoc """
  The Streaming context.

  Manages live events, tickets, chat, and reminders. All operations are scoped
  to an organization for multi-tenant isolation.

  Access control:
    * `subscribers_only` — viewer must have subscription_status in
      `["active", "trial", "past_due"]`
    * `public` — anyone can watch (viewer may be nil)
    * `pay_per_view` — viewer must have a non-expired ticket for the event
  """

  import Ecto.Query, warn: false

  require Marquee.Otel
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Marquee.Accounts.Organization
  alias Marquee.Accounts.Scope
  alias Marquee.Content.Video
  alias Marquee.Events
  alias Marquee.Pagination
  alias Marquee.Repo
  alias Marquee.Streaming.ChatMessage
  alias Marquee.Streaming.LiveEvent
  alias Marquee.Streaming.LiveEventChatBan
  alias Marquee.Streaming.LiveEventNotifier
  alias Marquee.Streaming.LiveEventReminder
  alias Marquee.Streaming.LiveEventTicket
  alias Marquee.Viewers.Viewer
  alias Marquee.Workers.RefundPpvTicketsWorker

  # Active subscription statuses that grant access to subscribers-only events
  @active_subscription_statuses ~w(active trial past_due)

  ## ---------------------------------------------------------------------------
  ## Live Event queries
  ## ---------------------------------------------------------------------------

  @doc """
  Returns a paginated list of live events for an organization.

  Accepts optional filters:
    * `:status` — filter by a specific status string
    * `:page` / `:per_page` — pagination

  Excludes soft-deleted events by default.

  Exempt from doctest — hits the database.
  """
  def list_live_events(%Organization{id: org_id}, opts \\ []) do
    LiveEvent
    |> where(organization_id: ^org_id)
    |> where([e], is_nil(e.deleted_at))
    |> apply_status_filter(Keyword.get(opts, :status))
    |> order_by(asc: :scheduled_start_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single live event by ID within an organization.

  Returns `{:ok, event}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_live_event(%Organization{id: org_id}, id) do
    case Repo.get_by(LiveEvent, id: id, organization_id: org_id) do
      nil -> {:error, :not_found}
      event -> {:ok, event}
    end
  end

  @doc """
  Gets a single live event by slug within an organization.

  Returns `{:ok, event}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_live_event_by_slug(%Organization{id: org_id}, slug) do
    case Repo.get_by(LiveEvent, slug: slug, organization_id: org_id) do
      nil -> {:error, :not_found}
      event -> {:ok, event}
    end
  end

  @doc """
  Preloads the recording video association onto a live event.

  Use this when rendering the ended-event view to access `recording_video`.
  Returns the event struct with `recording_video` loaded (or nil if no recording).

  Exempt from doctest — hits the database.
  """
  def preload_recording_video(%LiveEvent{} = event) do
    Repo.preload(event, :recording_video)
  end

  @doc """
  Gets a live event by its Mux live stream ID.

  This is intentionally cross-tenant: Mux webhooks arrive without org context,
  so we must look up by Mux stream ID. Only used by the webhook processor.

  Returns `{:ok, event}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_live_event_by_mux_stream_id(mux_live_stream_id) do
    case Repo.get_by(LiveEvent, mux_live_stream_id: mux_live_stream_id) do
      nil -> {:error, :not_found}
      event -> {:ok, event}
    end
  end

  @doc """
  Creates a live event, provisions a Mux live stream, and stores credentials.

  The Mux stream is provisioned in the same DB transaction. If the Mux API
  call fails, the transaction is rolled back and no record is persisted.

  Broadcasts `{:live_event_created, event}` on success.

  Exempt from doctest — hits the database and external service.
  """
  def create_live_event(%Scope{} = scope, attrs) do
    Tracer.with_span "marquee.streaming.create_live_event" do
      changeset = LiveEvent.changeset(%LiveEvent{}, attrs)

      Repo.transaction(fn ->
        with {:ok, event} <- insert_or_rollback(changeset),
             {:ok, stream_data} <- provision_mux_live_stream(event),
             {:ok, event} <- update_event_with_mux_data(event, stream_data) do
          Events.broadcast(scope, {:live_event_created, event})
          event
        else
          {:error, :validation, cs} -> Repo.rollback({:validation, cs})
          {:error, :mux_error, details} -> Repo.rollback({:mux_error, details})
        end
      end)
      |> unwrap_transaction_result()
    end
  end

  @doc """
  Updates a live event's attributes.

  Broadcasts `{:live_event_updated, event}` on success.

  Exempt from doctest — hits the database.
  """
  def update_live_event(%Scope{} = scope, %LiveEvent{} = event, attrs) do
    event
    |> LiveEvent.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Events.broadcast(scope, {:live_event_updated, updated})
        {:ok, updated}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  @doc """
  Cancels a live event by transitioning it to the `canceled` status.

  Broadcasts `{:live_event_status_changed, event}` on success and enqueues
  a `NotifyCancellationWorker` to email affected viewers.

  For pay-per-view events, dispatches a `RefundPpvTicketsWorker` Oban job to
  issue Stripe refunds for all non-refunded tickets.

  Exempt from doctest — hits the database.
  """
  def cancel_live_event(%Scope{} = scope, %LiveEvent{} = event) do
    case transition_event(scope, event, "canceled") do
      {:ok, canceled_event} = result ->
        org = Repo.get!(Organization, canceled_event.organization_id)
        LiveEventNotifier.send_cancellation_emails(canceled_event, org)

        if canceled_event.access_type == "pay_per_view" do
          %{
            "live_event_id" => canceled_event.id,
            "organization_id" => canceled_event.organization_id
          }
          |> RefundPpvTicketsWorker.new()
          |> Oban.insert()
        end

        result

      error ->
        error
    end
  end

  @doc """
  Soft-deletes a live event and deletes the associated Mux live stream.

  Broadcasts `{:live_event_deleted, event}` on success.

  Exempt from doctest — hits the database and external service.
  """
  def delete_live_event(%Scope{} = scope, %LiveEvent{} = event) do
    mux_client = Application.get_env(:marquee, :mux_client, Marquee.Content.MuxClient)

    if event.mux_live_stream_id do
      case mux_client.delete_live_stream(event.mux_live_stream_id) do
        :ok ->
          :ok

        {:error, :mux_error, details} ->
          Logger.warning("Mux delete failed during soft delete", reason: inspect(details))
      end
    end

    event
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
    |> case do
      {:ok, deleted} ->
        Events.broadcast(scope, {:live_event_deleted, deleted})
        {:ok, deleted}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  ## ---------------------------------------------------------------------------
  ## State machine
  ## ---------------------------------------------------------------------------

  @doc """
  Applies a status transition to a live event.

  Validates the transition is allowed per the state machine defined in
  `Marquee.Streaming.LiveEvent`. Returns `{:error, :invalid_transition}` if
  the transition is not permitted.

  Broadcasts `{:live_event_status_changed, event}` on success.

  Exempt from doctest — hits the database.
  """
  def transition_event(%Scope{} = scope, %LiveEvent{} = event, new_status) do
    Marquee.Otel.with_span "marquee.streaming.transition_event",
                           %{
                             org_id: event.organization_id,
                             live_event_id: event.id,
                             to_status: new_status
                           } do
      case LiveEvent.transition_changeset(event, event.status, new_status) do
        {:error, :invalid_transition} ->
          {:error, :invalid_transition}

        changeset ->
          changeset
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Events.broadcast(scope, {:live_event_status_changed, updated})
              Marquee.Metrics.live_event_transitioned(updated.organization_id, new_status)
              {:ok, updated}

            {:error, cs} ->
              {:error, :validation, cs}
          end
      end
    end
  end

  ## ---------------------------------------------------------------------------
  ## Credentials (never stored, fetched from Mux on demand)
  ## ---------------------------------------------------------------------------

  @doc """
  Fetches live stream credentials from Mux and returns the RTMP URL and stream key.

  Stream keys are never stored in the database. This function fetches them
  from the Mux API on demand.

  Returns `{:ok, %{rtmp_url: rtmp_url, stream_key: stream_key}}` or
  `{:error, :mux_error, details}`.

  Exempt from doctest — calls external service.
  """
  def get_stream_credentials(%LiveEvent{mux_live_stream_id: nil}) do
    {:error, :not_found}
  end

  def get_stream_credentials(%LiveEvent{mux_live_stream_id: stream_id} = event) do
    mux_client = Application.get_env(:marquee, :mux_client, Marquee.Content.MuxClient)

    case mux_client.get_live_stream(stream_id) do
      {:ok, stream_data} ->
        stream_key = stream_data["stream_key"]
        rtmp_url = event.mux_rtmp_url || "rtmps://global-live.mux.com:443/app"
        {:ok, %{rtmp_url: rtmp_url, stream_key: stream_key}}

      error ->
        error
    end
  end

  @doc """
  Regenerates the stream key for a live event via Mux API.

  Broadcasts `{:live_event_stream_key_regenerated, event}` on success.

  Exempt from doctest — calls external service.
  """
  def regenerate_stream_key(%Scope{} = scope, %LiveEvent{mux_live_stream_id: nil}) do
    _ = scope
    {:error, :not_found}
  end

  def regenerate_stream_key(%Scope{} = scope, %LiveEvent{} = event) do
    mux_client = Application.get_env(:marquee, :mux_client, Marquee.Content.MuxClient)

    case mux_client.reset_stream_key(event.mux_live_stream_id) do
      {:ok, _stream_data} ->
        Events.broadcast(scope, {:live_event_stream_key_regenerated, event})
        :ok

      error ->
        error
    end
  end

  ## ---------------------------------------------------------------------------
  ## Access control
  ## ---------------------------------------------------------------------------

  @doc """
  Returns true if the viewer can watch the event, false otherwise.

  Access rules:
    * `public` — always true (viewer can be nil)
    * `subscribers_only` — viewer has subscription_status in active statuses
    * `pay_per_view` — viewer has a non-expired ticket

  ## Examples

      iex> event = %Marquee.Streaming.LiveEvent{access_type: "public", status: "live"}
      iex> Marquee.Streaming.can_watch_event?(event, nil)
      true

      iex> event = %Marquee.Streaming.LiveEvent{access_type: "subscribers_only", status: "live"}
      iex> Marquee.Streaming.can_watch_event?(event, nil)
      false

      iex> event = %Marquee.Streaming.LiveEvent{access_type: "subscribers_only", status: "live"}
      iex> viewer = %Marquee.Viewers.Viewer{subscription_status: "active"}
      iex> Marquee.Streaming.can_watch_event?(event, viewer)
      true

      iex> event = %Marquee.Streaming.LiveEvent{access_type: "subscribers_only", status: "live"}
      iex> viewer = %Marquee.Viewers.Viewer{subscription_status: "trial"}
      iex> Marquee.Streaming.can_watch_event?(event, viewer)
      true

      iex> event = %Marquee.Streaming.LiveEvent{access_type: "subscribers_only", status: "live"}
      iex> viewer = %Marquee.Viewers.Viewer{subscription_status: "canceled"}
      iex> Marquee.Streaming.can_watch_event?(event, viewer)
      false

      iex> event = %Marquee.Streaming.LiveEvent{access_type: "pay_per_view", status: "live"}
      iex> Marquee.Streaming.can_watch_event?(event, nil)
      false
  """
  def can_watch_event?(%LiveEvent{access_type: "public"}, _viewer), do: true

  def can_watch_event?(%LiveEvent{access_type: "subscribers_only"}, nil), do: false

  def can_watch_event?(%LiveEvent{access_type: "subscribers_only"}, %Viewer{} = viewer) do
    viewer.subscription_status in @active_subscription_statuses
  end

  def can_watch_event?(%LiveEvent{access_type: "pay_per_view"}, nil), do: false

  def can_watch_event?(%LiveEvent{access_type: "pay_per_view"} = event, %Viewer{} = viewer) do
    now = DateTime.utc_now()

    LiveEventTicket
    |> where(live_event_id: ^event.id, viewer_id: ^viewer.id)
    |> where([t], is_nil(t.deleted_at))
    |> where([t], is_nil(t.refunded_at))
    |> where([t], t.access_ends_at > ^now)
    |> Repo.exists?()
  end

  @doc """
  Checks if a viewer can watch an event, returning a tagged result.

  Returns `{:ok, :allowed}` if access is granted, or `{:error, :access_denied, reason}`
  where reason is one of `:no_subscription`, `:no_ticket`, `:ticket_expired`, or
  `:viewer_banned`.

  ## Examples

      iex> event = %Marquee.Streaming.LiveEvent{access_type: "public", status: "live"}
      iex> Marquee.Streaming.check_event_access(event, nil)
      {:ok, :allowed}

      iex> event = %Marquee.Streaming.LiveEvent{access_type: "subscribers_only", status: "live"}
      iex> viewer = %Marquee.Viewers.Viewer{subscription_status: "none"}
      iex> Marquee.Streaming.check_event_access(event, viewer)
      {:error, :access_denied, :no_subscription}
  """
  def check_event_access(%LiveEvent{access_type: "public"}, _viewer), do: {:ok, :allowed}

  def check_event_access(%LiveEvent{access_type: "subscribers_only"}, nil) do
    {:error, :access_denied, :no_subscription}
  end

  def check_event_access(%LiveEvent{access_type: "subscribers_only"} = event, %Viewer{} = viewer) do
    if can_watch_event?(event, viewer) do
      {:ok, :allowed}
    else
      {:error, :access_denied, :no_subscription}
    end
  end

  def check_event_access(%LiveEvent{access_type: "pay_per_view"}, nil) do
    {:error, :access_denied, :no_ticket}
  end

  def check_event_access(%LiveEvent{access_type: "pay_per_view"} = event, %Viewer{} = viewer) do
    now = DateTime.utc_now()

    ticket =
      LiveEventTicket
      |> where(live_event_id: ^event.id, viewer_id: ^viewer.id)
      |> where([t], is_nil(t.deleted_at))
      |> where([t], is_nil(t.refunded_at))
      |> Repo.one()

    cond do
      is_nil(ticket) ->
        {:error, :access_denied, :no_ticket}

      DateTime.compare(ticket.access_ends_at, now) != :gt ->
        {:error, :access_denied, :ticket_expired}

      true ->
        {:ok, :allowed}
    end
  end

  ## ---------------------------------------------------------------------------
  ## PPV Tickets
  ## ---------------------------------------------------------------------------

  @doc """
  Returns a paginated list of tickets for a live event.

  Exempt from doctest — hits the database.
  """
  def list_tickets(%Organization{id: org_id}, %LiveEvent{id: event_id}, opts \\ []) do
    LiveEventTicket
    |> where(organization_id: ^org_id, live_event_id: ^event_id)
    |> where([t], is_nil(t.deleted_at))
    |> order_by(asc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns a paginated list of viewers with unrefunded tickets for a live event.

  Used by the cancellation worker to notify PPV ticket holders when an event
  is canceled. Only returns tickets that have not been refunded, so viewers
  who have already been refunded are not notified again.

  Exempt from doctest — hits the database.
  """
  def list_unrefunded_ticket_viewers(%LiveEvent{id: event_id}, opts \\ []) do
    LiveEventTicket
    |> where(live_event_id: ^event_id)
    |> where([t], is_nil(t.deleted_at))
    |> where([t], is_nil(t.refunded_at))
    |> preload(:viewer)
    |> order_by(asc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Creates a ticket granting a viewer access to a pay-per-view event.

  The access window is calculated based on the purchase time, event start time,
  and event's `ppv_access_window_hours`.

  Exempt from doctest — hits the database.
  """
  def create_ticket(%LiveEvent{} = event, %Viewer{} = viewer, attrs) do
    Marquee.Otel.with_span "marquee.streaming.create_ticket",
                           %{org_id: event.organization_id, live_event_id: event.id} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      access_starts_at = calculate_access_starts_at(event, now)
      window_seconds = (event.ppv_access_window_hours || 48) * 3600
      access_ends_at = DateTime.add(access_starts_at, window_seconds, :second)

      attrs =
        attrs
        |> Map.merge(%{
          organization_id: event.organization_id,
          live_event_id: event.id,
          viewer_id: viewer.id,
          access_starts_at: access_starts_at,
          access_ends_at: access_ends_at
        })

      %LiveEventTicket{}
      |> LiveEventTicket.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, ticket} ->
          Events.broadcast(
            %{organization: %{id: event.organization_id}},
            {:ticket_created, ticket}
          )

          Marquee.Metrics.ppv_ticket_created(event.organization_id)
          {:ok, ticket}

        {:error, changeset} ->
          {:error, :validation, changeset}
      end
    end
  end

  @doc """
  Gets the ticket for a specific viewer and event.

  Returns `{:ok, ticket}` or `{:error, :not_found}`.

  Exempt from doctest — hits the database.
  """
  def get_ticket_for_viewer(%LiveEvent{id: event_id}, %Viewer{id: viewer_id}) do
    case Repo.get_by(LiveEventTicket, live_event_id: event_id, viewer_id: viewer_id) do
      nil -> {:error, :not_found}
      ticket -> {:ok, ticket}
    end
  end

  @doc """
  Marks a ticket as refunded.

  Exempt from doctest — hits the database.
  """
  def refund_ticket(%Scope{} = scope, %LiveEventTicket{} = ticket) do
    ticket
    |> LiveEventTicket.refund_changeset(%{
      refunded_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Events.broadcast(scope, {:ticket_refunded, updated})
        {:ok, updated}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  ## ---------------------------------------------------------------------------
  ## Chat
  ## ---------------------------------------------------------------------------

  @doc """
  Returns paginated chat messages for a live event, ordered by insertion time.

  Excludes soft-deleted messages.

  Exempt from doctest — hits the database.
  """
  def list_chat_messages(%LiveEvent{id: event_id}, opts \\ []) do
    ChatMessage
    |> where(live_event_id: ^event_id)
    |> where([m], is_nil(m.deleted_at))
    |> order_by(asc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  @doc """
  Posts a chat message from a viewer.

  Validates that the event is live, the viewer has access, the viewer is not
  banned, and the content is within the 500-character limit.

  Broadcasts `{:chat_message_posted, message}` on success.

  Exempt from doctest — hits the database.
  """
  def post_chat_message(%LiveEvent{} = event, %Viewer{} = viewer, content) do
    Marquee.Otel.with_span "marquee.streaming.post_chat_message",
                           %{org_id: event.organization_id, live_event_id: event.id} do
      with :ok <- require_event_live(event),
           {:ok, :allowed} <- check_event_access(event, viewer),
           false <- viewer_banned?(event, viewer) do
        %ChatMessage{}
        |> ChatMessage.changeset(%{
          content: content,
          organization_id: event.organization_id,
          live_event_id: event.id,
          viewer_id: viewer.id
        })
        |> Repo.insert()
        |> case do
          {:ok, message} ->
            Events.broadcast(
              %{organization: %{id: event.organization_id}},
              {:chat_message_posted, message}
            )

            Marquee.Metrics.chat_message_sent(event.organization_id)
            {:ok, message}

          {:error, changeset} ->
            {:error, :validation, changeset}
        end
      else
        {:error, :event_not_live} -> {:error, :event_not_live}
        {:error, :access_denied, reason} -> {:error, :access_denied, reason}
        true -> {:error, :access_denied, :viewer_banned}
      end
    end
  end

  @doc """
  Soft-deletes a chat message (moderation).

  Broadcasts `{:chat_message_deleted, message}` on success.

  Exempt from doctest — hits the database.
  """
  def delete_chat_message(%Scope{} = scope, %ChatMessage{} = message) do
    message
    |> ChatMessage.delete_changeset(%{
      deleted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      deleted_by_user_id: scope.user && scope.user.id
    })
    |> Repo.update()
    |> case do
      {:ok, deleted} ->
        Events.broadcast(scope, {:chat_message_deleted, deleted})
        {:ok, deleted}

      {:error, changeset} ->
        {:error, :validation, changeset}
    end
  end

  @doc """
  Bans a viewer from chat in a specific live event.

  Returns `{:error, :already_banned}` if the viewer is already banned.

  Broadcasts `{:viewer_banned_from_chat, %{event: event, viewer: viewer}}` on success.

  Exempt from doctest — hits the database.
  """
  def ban_viewer_from_chat(%Scope{} = scope, %LiveEvent{} = event, %Viewer{} = viewer) do
    %LiveEventChatBan{}
    |> LiveEventChatBan.changeset(%{
      organization_id: event.organization_id,
      live_event_id: event.id,
      viewer_id: viewer.id,
      banned_by_user_id: scope.user.id
    })
    |> Repo.insert()
    |> case do
      {:ok, _ban} ->
        Events.broadcast(scope, {:viewer_banned_from_chat, %{event: event, viewer: viewer}})
        :ok

      {:error, %Ecto.Changeset{errors: [_ | _]} = cs} ->
        if unique_constraint_error?(cs, [:live_event_id, :viewer_id]) do
          {:error, :already_banned}
        else
          {:error, :validation, cs}
        end
    end
  end

  @doc """
  Returns true if the viewer is banned from chat in the given event.

  ## Examples

      iex> event = %Marquee.Streaming.LiveEvent{id: nil}
      iex> viewer = %Marquee.Viewers.Viewer{id: nil}
      iex> Marquee.Streaming.viewer_banned?(event, viewer)
      false
  """
  def viewer_banned?(%LiveEvent{id: event_id}, %Viewer{id: viewer_id}) do
    LiveEventChatBan
    |> where(live_event_id: ^event_id, viewer_id: ^viewer_id)
    |> Repo.exists?()
  end

  ## ---------------------------------------------------------------------------
  ## Reminders
  ## ---------------------------------------------------------------------------

  @doc """
  Adds a reminder for a viewer for a live event.

  Returns `{:error, :already_set}` if the reminder already exists.

  Exempt from doctest — hits the database.
  """
  def add_reminder(%LiveEvent{} = event, %Viewer{} = viewer) do
    %LiveEventReminder{}
    |> LiveEventReminder.changeset(%{
      organization_id: event.organization_id,
      live_event_id: event.id,
      viewer_id: viewer.id
    })
    |> Repo.insert()
    |> case do
      {:ok, reminder} ->
        {:ok, reminder}

      {:error, cs} ->
        if unique_constraint_error?(cs, [:live_event_id, :viewer_id]) do
          {:error, :already_set}
        else
          {:error, :validation, cs}
        end
    end
  end

  @doc """
  Removes a reminder for a viewer for a live event.

  Returns `:ok` whether or not the reminder existed.

  Exempt from doctest — hits the database.
  """
  def remove_reminder(%LiveEvent{id: event_id}, %Viewer{id: viewer_id}) do
    LiveEventReminder
    |> where(live_event_id: ^event_id, viewer_id: ^viewer_id)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Returns true if the viewer has a reminder set for the event.

  ## Examples

      iex> event = %Marquee.Streaming.LiveEvent{id: nil}
      iex> viewer = %Marquee.Viewers.Viewer{id: nil}
      iex> Marquee.Streaming.has_reminder?(event, viewer)
      false
  """
  def has_reminder?(%LiveEvent{id: event_id}, %Viewer{id: viewer_id}) do
    LiveEventReminder
    |> where(live_event_id: ^event_id, viewer_id: ^viewer_id)
    |> Repo.exists?()
  end

  @doc """
  Returns a paginated list of viewers who have set reminders for an event.

  Exempt from doctest — hits the database.
  """
  def list_reminder_viewers(%LiveEvent{id: event_id}, opts \\ []) do
    LiveEventReminder
    |> where(live_event_id: ^event_id)
    |> where([r], is_nil(r.notified_at))
    |> preload(:viewer)
    |> order_by(asc: :inserted_at)
    |> Pagination.paginate(opts)
  end

  ## ---------------------------------------------------------------------------
  ## Private helpers
  ## ---------------------------------------------------------------------------

  defp apply_status_filter(query, nil), do: query
  defp apply_status_filter(query, status), do: where(query, [e], e.status == ^status)

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> {:ok, record}
      {:error, cs} -> {:error, :validation, cs}
    end
  end

  defp provision_mux_live_stream(event) do
    mux_client = Application.get_env(:marquee, :mux_client, Marquee.Content.MuxClient)

    params = %{
      "playback_policy" => ["public"],
      "new_asset_settings" => %{
        "playback_policy" => ["public"]
      },
      "reduced_latency" => false,
      "reconnect_window" => 60,
      "max_continuous_duration" => 43_200,
      "passthrough" => event.id
    }

    mux_client.create_live_stream(params)
  end

  defp update_event_with_mux_data(event, stream_data) do
    playback_ids = stream_data["playback_ids"] || []
    public_pb = Enum.find(playback_ids, &(&1["policy"] == "public"))

    mux_attrs = %{
      mux_live_stream_id: stream_data["id"],
      mux_live_playback_id: public_pb && public_pb["id"],
      mux_rtmp_url: "rtmps://global-live.mux.com:443/app"
    }

    event
    |> LiveEvent.mux_changeset(mux_attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, cs} -> {:error, :validation, cs}
    end
  end

  defp unwrap_transaction_result({:ok, event}), do: {:ok, event}

  defp unwrap_transaction_result({:error, {:validation, changeset}}) do
    {:error, :validation, changeset}
  end

  defp unwrap_transaction_result({:error, {:mux_error, details}}) do
    {:error, :mux_error, details}
  end

  defp unwrap_transaction_result({:error, other}), do: {:error, other}

  defp require_event_live(%LiveEvent{status: "live"}), do: :ok
  defp require_event_live(_event), do: {:error, :event_not_live}

  defp calculate_access_starts_at(event, now) do
    scheduled = event.scheduled_start_at

    if DateTime.compare(now, scheduled) == :gt do
      now
    else
      scheduled
    end
  end

  defp unique_constraint_error?(changeset, keys) do
    Enum.any?(changeset.errors, fn {k, {_msg, opts}} ->
      k in keys && Keyword.get(opts, :constraint) == :unique
    end)
  end

  defp link_recording_to_event(%LiveEvent{} = event, asset_data) do
    org = Repo.get!(Organization, event.organization_id)

    video_attrs = %{
      title: event.title,
      slug: "recording-#{event.id}",
      organization_id: event.organization_id,
      mux_asset_id: asset_data["id"],
      mux_status: "preparing",
      is_recording: true
    }

    Repo.transaction(fn ->
      with {:ok, video} <- insert_recording_video(video_attrs),
           {:ok, updated_event} <- attach_recording_to_event(event, video) do
        Events.broadcast(
          %{organization: org},
          {:live_event_recording_ready, updated_event}
        )

        updated_event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_recording_video(attrs) do
    %Video{}
    |> Video.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, video} -> {:ok, video}
      {:error, cs} -> {:error, {:validation, cs}}
    end
  end

  defp attach_recording_to_event(event, video) do
    event
    |> LiveEvent.mux_changeset(%{recording_video_id: video.id})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, cs} -> {:error, {:validation, cs}}
    end
  end

  # Make link_recording_to_event accessible to the webhook processor
  @doc false
  def handle_recording_completed(mux_live_stream_id, asset_data) do
    case get_live_event_by_mux_stream_id(mux_live_stream_id) do
      {:ok, %{recording_video_id: vid_id}} when not is_nil(vid_id) ->
        # Already linked — idempotent no-op
        :ok

      {:ok, event} ->
        case link_recording_to_event(event, asset_data) do
          {:ok, _event} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        Logger.warning("No live event found for completed recording",
          mux_live_stream_id: mux_live_stream_id
        )

        :ok
    end
  end
end
