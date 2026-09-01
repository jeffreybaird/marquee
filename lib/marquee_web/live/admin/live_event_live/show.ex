defmodule MarqueeWeb.Admin.LiveEventLive.Show do
  @moduledoc """
  Detail view for a live event. Shows all event fields, state transition
  buttons, and streaming credentials (fetched on demand — never pre-rendered).

  Stream keys are NEVER pre-loaded into assigns. They are fetched from Mux
  only when the operator explicitly clicks "Get RTMP Credentials".

  Route: GET /admin/live-events/:slug
  """

  use MarqueeWeb, :live_view

  alias Marquee.Events
  alias Marquee.Streaming

  @credential_statuses ~w(draft scheduled live)

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    org = socket.assigns.organization

    case Streaming.get_live_event_by_slug(org, slug) do
      {:ok, event} ->
        if connected?(socket) do
          Events.subscribe(org.id)
        end

        mod_messages =
          if event.status == "live",
            do: Streaming.list_chat_messages(event, per_page: 50).results,
            else: []

        {:ok,
         socket
         |> assign(:page_title, event.title)
         |> assign(:event, event)
         |> assign(:show_credentials_modal, false)
         |> assign(:credentials, nil)
         |> assign(:credentials_loading, false)
         |> assign(:show_delete_confirm, false)
         |> assign(:mod_chat_messages, mod_messages)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Live event not found.")
         |> push_navigate(to: ~p"/admin/live-events")}
    end
  end

  @impl true
  def handle_event("delete_chat_message", %{"id" => msg_id}, socket) do
    scope = socket.assigns.current_scope
    msg = Enum.find(socket.assigns.mod_chat_messages, &(&1.id == msg_id))

    if msg do
      case Streaming.delete_chat_message(scope, msg) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(
             :mod_chat_messages,
             Enum.reject(socket.assigns.mod_chat_messages, &(&1.id == msg_id))
           )
           |> put_flash(:info, "Message deleted.")}

        {:error, :validation, _cs} ->
          {:noreply, put_flash(socket, :error, "Failed to delete message.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("ban_viewer", %{"viewer-id" => viewer_id}, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event
    org = socket.assigns.organization

    case Marquee.Viewers.get_viewer(org, viewer_id) do
      {:ok, viewer} ->
        case Streaming.ban_viewer_from_chat(scope, event, viewer) do
          :ok ->
            {:noreply, put_flash(socket, :info, "Viewer banned.")}

          {:error, :already_banned} ->
            {:noreply, put_flash(socket, :info, "Viewer already banned.")}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to ban viewer.")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Viewer not found.")}
    end
  end

  @impl true
  def handle_event("transition", %{"status" => new_status}, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event

    case Streaming.transition_event(scope, event, new_status) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:event, updated)
         |> put_flash(:info, "Event status updated to #{format_status(new_status)}.")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "That status transition is not allowed.")}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update event status.")}
    end
  end

  @impl true
  def handle_event("show_credentials", _params, socket) do
    event = socket.assigns.event

    socket = assign(socket, :credentials_loading, true)

    case Streaming.get_stream_credentials(event) do
      {:ok, creds} ->
        {:noreply,
         socket
         |> assign(:credentials, creds)
         |> assign(:show_credentials_modal, true)
         |> assign(:credentials_loading, false)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:credentials_loading, false)
         |> put_flash(:error, "No Mux stream is associated with this event.")}

      {:error, :mux_error, _details} ->
        {:noreply,
         socket
         |> assign(:credentials_loading, false)
         |> put_flash(:error, "Could not fetch credentials from Mux.")}
    end
  end

  @impl true
  def handle_event("close_credentials", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_credentials_modal, false)
     |> assign(:credentials, nil)}
  end

  @impl true
  def handle_event("regenerate_stream_key", _params, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event

    case Streaming.regenerate_stream_key(scope, event) do
      :ok ->
        # Re-fetch credentials to show the new key
        case Streaming.get_stream_credentials(event) do
          {:ok, creds} ->
            {:noreply,
             socket
             |> assign(:credentials, creds)
             |> put_flash(:info, "Stream key regenerated.")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:show_credentials_modal, false)
             |> assign(:credentials, nil)
             |> put_flash(:info, "Stream key regenerated. Click 'Get RTMP Credentials' to view.")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No Mux stream associated with this event.")}

      {:error, :mux_error, _details} ->
        {:noreply, put_flash(socket, :error, "Could not regenerate stream key.")}
    end
  end

  @impl true
  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, true)}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event

    case Streaming.delete_live_event(scope, event) do
      {:ok, _deleted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Live event deleted.")
         |> push_navigate(to: ~p"/admin/live-events")}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete event.")}
    end
  end

  @impl true
  def handle_info({:marquee_event, {:live_event_status_changed, updated}, _scope}, socket) do
    if socket.assigns.event.id == updated.id do
      {:noreply, assign(socket, :event, updated)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:marquee_event, {:live_event_updated, updated}, _scope}, socket) do
    if socket.assigns.event.id == updated.id do
      {:noreply, assign(socket, :event, updated)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:marquee_event, {:chat_message_posted, msg}, _scope}, socket) do
    if msg.live_event_id == socket.assigns.event.id do
      {:noreply, assign(socket, :mod_chat_messages, socket.assigns.mod_chat_messages ++ [msg])}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:marquee_event, {:chat_message_deleted, msg}, _scope}, socket) do
    if msg.live_event_id == socket.assigns.event.id do
      updated = Enum.reject(socket.assigns.mod_chat_messages, &(&1.id == msg.id))
      {:noreply, assign(socket, :mod_chat_messages, updated)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:marquee_event, _event, _scope}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :show_credentials, assigns.event.status in @credential_statuses)

    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      trial_status={@trial_status}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
      flash={@flash}
    >
      <%!-- Header --%>
      <div class="flex items-start justify-between">
        <div>
          <.header>
            {@event.title}
            <:subtitle>
              <span class="font-mono text-xs">{@event.slug}</span>
            </:subtitle>
          </.header>
        </div>
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/admin/live-events/#{@event.slug}/edit"}
            class="inline-flex items-center gap-1.5 rounded-md border border-admin-border px-3 py-1.5 font-ui text-sm text-admin-fg hover:bg-admin-card"
            data-test="edit-btn"
          >
            Edit
          </.link>
          <button
            phx-click="confirm_delete"
            class="inline-flex items-center gap-1.5 rounded-md border border-error/40 px-3 py-1.5 font-ui text-sm text-error hover:bg-error/10"
            data-test="delete-btn"
          >
            Delete
          </button>
        </div>
      </div>

      <%!-- Status badge --%>
      <div class="mt-2">
        <span class={"rounded-full px-3 py-1 font-ui text-sm #{status_badge(@event.status)}"}>
          {format_status(@event.status)}
        </span>
      </div>

      <%!-- State transition buttons --%>
      <div class="mt-4 flex flex-wrap gap-2" data-test="transition-buttons">
        <%!-- Draft → scheduled --%>
        <button
          :if={@event.status == "draft"}
          phx-click="transition"
          phx-value-status="scheduled"
          class="rounded-md bg-info/10 border border-info/40 px-4 py-2 font-ui text-sm text-admin-fg hover:bg-info/20"
          data-test="btn-schedule"
        >
          Schedule
        </button>

        <%!-- Scheduled → live --%>
        <button
          :if={@event.status == "scheduled"}
          phx-click="transition"
          phx-value-status="live"
          class="rounded-md bg-error/10 border border-error/40 px-4 py-2 font-ui text-sm text-error hover:bg-error/20"
          data-test="btn-go-live"
        >
          Go Live
        </button>

        <%!-- Scheduled → canceled --%>
        <button
          :if={@event.status in ["draft", "scheduled"]}
          phx-click="transition"
          phx-value-status="canceled"
          class="rounded-md border border-admin-border px-4 py-2 font-ui text-sm text-admin-muted hover:bg-admin-card"
          data-test="btn-cancel"
        >
          Cancel
        </button>

        <%!-- Scheduled → did_not_occur --%>
        <button
          :if={@event.status == "scheduled"}
          phx-click="transition"
          phx-value-status="did_not_occur"
          class="rounded-md border border-warning/40 bg-warning/10 px-4 py-2 font-ui text-sm text-warning hover:bg-warning/20"
          data-test="btn-did-not-occur"
        >
          Mark as Did Not Occur
        </button>

        <%!-- Live → ended --%>
        <button
          :if={@event.status == "live"}
          phx-click="transition"
          phx-value-status="ended"
          class="rounded-md border border-admin-border px-4 py-2 font-ui text-sm text-admin-fg hover:bg-admin-card"
          data-test="btn-end-stream"
        >
          End Stream
        </button>
      </div>

      <%!-- Event details --%>
      <div class="mt-8 grid gap-6 sm:grid-cols-2" data-test="event-details">
        <dl class="space-y-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">Access</dt>
            <dd class="mt-1 text-sm text-admin-fg">{format_access_type(@event.access_type)}</dd>
          </div>
          <div :if={@event.access_type == "pay_per_view"}>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">PPV Price</dt>
            <dd class="mt-1 text-sm text-admin-fg">
              {format_price(@event.ppv_price_cents)}
            </dd>
          </div>
          <div :if={@event.access_type == "pay_per_view"}>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">
              Access Window
            </dt>
            <dd class="mt-1 text-sm text-admin-fg">
              {@event.ppv_access_window_hours} hours
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">
              Scheduled Start
            </dt>
            <dd class="mt-1 text-sm text-admin-fg">
              {format_datetime(@event.scheduled_start_at)}
            </dd>
          </div>
          <div :if={@event.estimated_duration_minutes}>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">
              Estimated Duration
            </dt>
            <dd class="mt-1 text-sm text-admin-fg">
              {@event.estimated_duration_minutes} min
            </dd>
          </div>
        </dl>
        <dl class="space-y-4">
          <div :if={@event.went_live_at}>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">Went Live</dt>
            <dd class="mt-1 text-sm text-admin-fg">{format_datetime(@event.went_live_at)}</dd>
          </div>
          <div :if={@event.ended_at}>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">Ended At</dt>
            <dd class="mt-1 text-sm text-admin-fg">{format_datetime(@event.ended_at)}</dd>
          </div>
          <div :if={@event.canceled_at}>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">Canceled At</dt>
            <dd class="mt-1 text-sm text-admin-fg">{format_datetime(@event.canceled_at)}</dd>
          </div>
          <div :if={@event.recording_video_id}>
            <dt class="text-xs font-medium uppercase tracking-wide text-admin-muted">Recording</dt>
            <dd class="mt-1 text-sm">
              <.link
                navigate={~p"/admin/content"}
                class="text-admin-accent hover:underline"
                data-test="recording-link"
              >
                View Recording
              </.link>
            </dd>
          </div>
        </dl>
      </div>

      <div :if={@event.description} class="mt-6">
        <h3 class="text-xs font-medium uppercase tracking-wide text-admin-muted">Description</h3>
        <p class="mt-1 text-sm text-admin-fg">{@event.description}</p>
      </div>

      <%!-- Chat moderation section --%>
      <section
        :if={@event.status == "live"}
        aria-label="Chat moderation"
        data-test="chat-moderation"
        class="mt-8"
      >
        <h2 class="op-section-title">Live Chat Moderation</h2>
        <div data-test="mod-message-list">
          <div
            :for={msg <- @mod_chat_messages}
            class="op-mod-message"
            data-test={"mod-message-#{msg.id}"}
          >
            <span class="op-mod-viewer">{String.slice(to_string(msg.viewer_id), 0, 8)}</span>
            <span class="op-mod-content">{msg.content}</span>
            <button
              phx-click="delete_chat_message"
              phx-value-id={msg.id}
              data-test={"delete-chat-msg-#{msg.id}"}
              aria-label="Delete message"
              class="op-btn-danger-sm"
            >
              Delete
            </button>
            <button
              phx-click="ban_viewer"
              phx-value-viewer-id={msg.viewer_id}
              data-test={"ban-viewer-#{msg.viewer_id}"}
              aria-label="Ban viewer from chat"
              class="op-btn-warning-sm"
            >
              Ban
            </button>
          </div>
          <p :if={@mod_chat_messages == []} data-test="mod-no-messages">No messages yet.</p>
        </div>
      </section>

      <%!-- Streaming credentials section --%>
      <section :if={@show_credentials} class="mt-8 rounded-lg border border-admin-border p-4">
        <h2 class="text-sm font-semibold text-admin-fg">Streaming Credentials</h2>
        <p class="mt-1 text-xs text-admin-muted">
          Credentials are fetched from Mux on demand and never stored in the page.
        </p>
        <div class="mt-3 flex gap-2">
          <button
            phx-click="show_credentials"
            disabled={@credentials_loading}
            class="inline-flex items-center gap-2 rounded-md bg-admin-accent px-3 py-1.5 font-ui text-sm font-medium text-white hover:opacity-90 disabled:opacity-60"
            data-test="get-credentials-btn"
          >
            {if @credentials_loading, do: "Loading…", else: "Get RTMP Credentials"}
          </button>
        </div>
      </section>

      <%!-- Credentials modal — stream key only visible here, never pre-rendered --%>
      <div
        :if={@show_credentials_modal && @credentials}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
        role="dialog"
        aria-modal="true"
        aria-labelledby="credentials-modal-title"
        data-test="credentials-modal"
      >
        <div class="w-full max-w-lg rounded-lg bg-admin-bg border border-admin-border p-6 shadow-lg">
          <div class="flex items-center justify-between">
            <h2 id="credentials-modal-title" class="text-base font-semibold text-admin-fg">
              RTMP Credentials
            </h2>
            <button
              phx-click="close_credentials"
              class="rounded-md p-1 text-admin-muted hover:text-admin-fg focus:outline-none focus:ring-2 focus:ring-admin-accent"
              aria-label="Close credentials modal"
              data-test="close-credentials-btn"
            >
              <span aria-hidden="true">&times;</span>
            </button>
          </div>

          <div class="mt-4 space-y-4">
            <div>
              <label class="block text-xs font-medium uppercase tracking-wide text-admin-muted">
                RTMP URL
              </label>
              <code
                class="mt-1 block rounded bg-admin-card px-3 py-2 font-mono text-sm text-admin-fg break-all"
                data-test="rtmp-url"
              >
                {@credentials.rtmp_url}
              </code>
            </div>
            <div>
              <label class="block text-xs font-medium uppercase tracking-wide text-admin-muted">
                Stream Key
              </label>
              <code
                class="mt-1 block rounded bg-admin-card px-3 py-2 font-mono text-sm text-admin-fg break-all"
                data-test="stream-key"
              >
                {@credentials.stream_key}
              </code>
            </div>
          </div>

          <div class="mt-6 flex gap-2">
            <button
              phx-click="regenerate_stream_key"
              class="rounded-md border border-warning/40 bg-warning/10 px-3 py-1.5 font-ui text-sm text-warning hover:bg-warning/20"
              data-test="regenerate-key-btn"
            >
              Regenerate Stream Key
            </button>
            <button
              phx-click="close_credentials"
              class="rounded-md border border-admin-border px-3 py-1.5 font-ui text-sm text-admin-fg hover:bg-admin-card"
              data-test="close-credentials-modal-btn"
            >
              Close
            </button>
          </div>
        </div>
      </div>

      <%!-- Delete confirmation modal --%>
      <div
        :if={@show_delete_confirm}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
        role="dialog"
        aria-modal="true"
        aria-labelledby="delete-confirm-title"
        data-test="delete-confirm-modal"
      >
        <div class="w-full max-w-sm rounded-lg bg-admin-bg border border-admin-border p-6 shadow-lg">
          <h2 id="delete-confirm-title" class="text-base font-semibold text-admin-fg">
            Delete Live Event?
          </h2>
          <p class="mt-2 text-sm text-admin-muted">
            This will soft-delete the event and remove the associated Mux stream. This action cannot be undone.
          </p>
          <div class="mt-4 flex gap-2">
            <button
              phx-click="delete"
              class="rounded-md bg-error px-4 py-2 font-ui text-sm font-medium text-white hover:opacity-90"
              data-test="confirm-delete-btn"
            >
              Delete
            </button>
            <button
              phx-click="cancel_delete"
              class="rounded-md border border-admin-border px-4 py-2 font-ui text-sm text-admin-fg hover:bg-admin-card"
              data-test="cancel-delete-btn"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp status_badge("live"), do: "border border-error/40 bg-error/10 text-error"
  defp status_badge("scheduled"), do: "border border-info/40 bg-info/10 text-admin-fg"
  defp status_badge("ended"), do: "bg-admin-card text-admin-muted"
  defp status_badge("canceled"), do: "bg-admin-card text-admin-muted"
  defp status_badge("did_not_occur"), do: "border border-warning/40 bg-warning/10 text-warning"
  defp status_badge(_), do: "bg-admin-card text-admin-muted"

  defp format_status("did_not_occur"), do: "Did Not Occur"
  defp format_status(status), do: String.capitalize(status)

  defp format_access_type("subscribers_only"), do: "Subscribers Only"
  defp format_access_type("pay_per_view"), do: "Pay Per View"
  defp format_access_type("public"), do: "Public"
  defp format_access_type(type), do: type

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M UTC")
  end

  defp format_price(nil), do: "—"

  defp format_price(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end
end
