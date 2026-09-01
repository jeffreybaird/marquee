defmodule MarqueeWeb.Super.OrganizationShowLive do
  @moduledoc """
  Organization detail page. Shows memberships, video count, subscriber count,
  live event count, feature flag management, live event status controls,
  and provides impersonation and soft-delete controls.

  Events: toggle_feature, advance_event_status, run_did_not_occur_check
  Route: /super/organizations/:id
  """

  use MarqueeWeb, :live_view

  alias Marquee.Accounts.Scope
  alias Marquee.Admin
  alias Marquee.Features
  alias Marquee.Streaming
  alias Marquee.Workers.MarkEventsDidNotOccurWorker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org = Admin.get_organization!(id)
    memberships = Admin.list_memberships(org)
    video_count = Admin.video_count(org)
    subscriber_count = Admin.subscriber_count(org)
    live_event_count = Admin.live_event_count(org)
    live_events = Streaming.list_live_events(org, per_page: 10).results
    known_features = Features.known_features()

    {:ok,
     socket
     |> assign(:page_title, org.name)
     |> assign(:current_path, "/super/organizations")
     |> assign(:current_user, socket.assigns.current_scope.user)
     |> assign(:org, org)
     |> assign(:memberships, memberships)
     |> assign(:video_count, video_count)
     |> assign(:subscriber_count, subscriber_count)
     |> assign(:live_event_count, live_event_count)
     |> assign(:live_events, live_events)
     |> assign(:known_features, known_features)}
  end

  @impl true
  def handle_event("toggle_feature", %{"feature" => feature}, socket) do
    org = socket.assigns.org
    current = Map.get(org.features || %{}, feature, false)
    new_features = Map.put(org.features || %{}, feature, !current)

    case Admin.update_organization(org, %{features: new_features}) do
      {:ok, updated} ->
        action = if current, do: "disabled", else: "enabled"

        {:noreply,
         socket
         |> assign(:org, updated)
         |> put_flash(:info, "Feature #{feature} #{action}.")}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update feature flag.")}
    end
  end

  @impl true
  def handle_event(
        "advance_event_status",
        %{"event-id" => event_id, "status" => new_status},
        socket
      ) do
    org = socket.assigns.org
    scope = %Scope{organization: org, user: socket.assigns.current_user}

    case Streaming.get_live_event(org, event_id) do
      {:ok, event} ->
        case Streaming.transition_event(scope, event, new_status) do
          {:ok, _} ->
            updated_events = Streaming.list_live_events(org, per_page: 10).results

            {:noreply,
             socket
             |> assign(:live_events, updated_events)
             |> put_flash(:info, "Event advanced to #{new_status}.")}

          {:error, :invalid_transition} ->
            {:noreply, put_flash(socket, :error, "Invalid transition.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to transition event.")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Event not found.")}
    end
  end

  @impl true
  def handle_event("run_did_not_occur_check", _params, socket) do
    MarkEventsDidNotOccurWorker.new(%{})
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Did-not-occur check queued.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.SuperLayout.super_layout
      current_path={@current_path}
      current_user={@current_user}
      flash={@flash}
    >
      <div class="flex items-start justify-between">
        <.header>
          {@org.name}
          <:subtitle>{@org.slug}</:subtitle>
        </.header>

        <div class="flex gap-3 mt-1">
          <.link navigate={~p"/super/organizations/#{@org.id}/edit"}>
            <.button>Edit</.button>
          </.link>
          <form action={~p"/super/organizations/#{@org.id}/impersonate"} method="post">
            <input
              type="hidden"
              name="_csrf_token"
              value={
                Plug.CSRFProtection.get_csrf_token_for(
                  ~p"/super/organizations/#{@org.id}/impersonate"
                )
              }
            />
            <.button type="submit" class="btn-warning" data-test="impersonate-btn">
              Open as Admin
            </.button>
          </form>
        </div>
      </div>

      <div class="mt-8 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.detail_card label="Custom Domain" value={@org.custom_domain || "None"} />
        <.detail_card label="Members" value={length(@memberships)} />
        <.detail_card label="Videos" value={@video_count} />
        <.detail_card label="Subscribers" value={@subscriber_count} />
        <.detail_card label="Live Events" value={@live_event_count} />
      </div>

      <section class="mt-8">
        <h2 class="text-base font-semibold mb-3">Members</h2>
        <table class="table w-full" data-test="members-table">
          <thead>
            <tr>
              <th>Email</th>
              <th>Role</th>
              <th>Joined</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={m <- @memberships} data-test={"member-row-#{m.id}"}>
              <td>{m.user.email}</td>
              <td>
                <span class="badge badge-sm">{m.role}</span>
              </td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(m.inserted_at, "%b %d, %Y")}
              </td>
            </tr>
          </tbody>
        </table>

        <p :if={@memberships == []} class="py-4 text-base-content/60" data-test="no-members">
          No members yet.
        </p>
      </section>

      <section :if={@org.themes != []} class="mt-8">
        <h2 class="text-base font-semibold mb-3">Theme</h2>
        <div class="flex gap-2">
          <.color_swatch color={hd(@org.themes).brand_primary} label="Brand Primary" />
          <.color_swatch color={hd(@org.themes).brand_secondary} label="Brand Secondary" />
          <.color_swatch color={hd(@org.themes).background} label="Background" />
          <.color_swatch color={hd(@org.themes).accent} label="Accent" />
        </div>
      </section>

      <section aria-labelledby="feature-flags-heading" class="mt-8" data-test="feature-flags-section">
        <h2 id="feature-flags-heading" class="text-base font-semibold mb-3">Feature Flags</h2>
        <ul class="divide-y divide-base-300" data-test="feature-flag-list">
          <li
            :for={feature <- @known_features}
            class="flex items-center justify-between py-2"
            data-test={"feature-flag-#{feature}"}
          >
            <span class="font-mono text-sm">{feature}</span>
            <button
              phx-click="toggle_feature"
              phx-value-feature={feature}
              aria-pressed={to_string(feature_enabled?(@org, feature))}
              class={[
                "btn btn-sm",
                if(feature_enabled?(@org, feature), do: "btn-success", else: "btn-outline")
              ]}
              data-test={"toggle-feature-#{feature}"}
            >
              {if feature_enabled?(@org, feature), do: "Enabled", else: "Disabled"}
            </button>
          </li>
        </ul>
      </section>

      <section aria-labelledby="live-events-heading" class="mt-8" data-test="live-events-section">
        <div class="flex items-center justify-between mb-3">
          <h2 id="live-events-heading" class="text-base font-semibold">Live Events</h2>
          <button
            phx-click="run_did_not_occur_check"
            class="btn btn-sm btn-outline"
            data-test="run-did-not-occur-check"
            aria-label="Mark stale scheduled events as did not occur"
          >
            Run Did-Not-Occur Check
          </button>
        </div>
        <table :if={@live_events != []} class="table w-full" data-test="live-events-table">
          <thead>
            <tr>
              <th>Title</th>
              <th>Status</th>
              <th>Scheduled</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={event <- @live_events} data-test={"live-event-row-#{event.id}"}>
              <td>{event.title}</td>
              <td>
                <span class="badge badge-sm" data-test={"event-status-#{event.id}"}>
                  {event.status}
                </span>
              </td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(event.scheduled_start_at, "%Y-%m-%d %H:%M UTC")}
              </td>
              <td class="flex gap-1">
                <button
                  :if={"scheduled" in next_states(event.status)}
                  phx-click="advance_event_status"
                  phx-value-event-id={event.id}
                  phx-value-status="scheduled"
                  class="btn btn-xs btn-outline"
                  data-test={"advance-#{event.id}-scheduled"}
                >
                  → Scheduled
                </button>
                <button
                  :if={"live" in next_states(event.status)}
                  phx-click="advance_event_status"
                  phx-value-event-id={event.id}
                  phx-value-status="live"
                  class="btn btn-xs btn-outline"
                  data-test={"advance-#{event.id}-live"}
                >
                  → Live
                </button>
                <button
                  :if={"ended" in next_states(event.status)}
                  phx-click="advance_event_status"
                  phx-value-event-id={event.id}
                  phx-value-status="ended"
                  class="btn btn-xs btn-outline"
                  data-test={"advance-#{event.id}-ended"}
                >
                  → Ended
                </button>
                <button
                  :if={"canceled" in next_states(event.status)}
                  phx-click="advance_event_status"
                  phx-value-event-id={event.id}
                  phx-value-status="canceled"
                  class="btn btn-xs btn-outline"
                  data-test={"advance-#{event.id}-canceled"}
                >
                  → Cancel
                </button>
                <button
                  :if={"did_not_occur" in next_states(event.status)}
                  phx-click="advance_event_status"
                  phx-value-event-id={event.id}
                  phx-value-status="did_not_occur"
                  class="btn btn-xs btn-outline"
                  data-test={"advance-#{event.id}-did-not-occur"}
                >
                  → Did Not Occur
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@live_events == []} class="py-4 text-base-content/60" data-test="no-live-events">
          No live events.
        </p>
      </section>
    </MarqueeWeb.Components.SuperLayout.super_layout>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp detail_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200 p-4">
      <p class="text-xs text-base-content/60">{@label}</p>
      <p class="mt-1 font-semibold text-base-content">{@value}</p>
    </div>
    """
  end

  attr :color, :string, required: true
  attr :label, :string, required: true

  defp color_swatch(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <div
        class="w-8 h-8 rounded border border-base-300"
        style={"background-color: #{@color}"}
      >
      </div>
      <span class="text-xs text-base-content/60">{@label}</span>
    </div>
    """
  end

  defp feature_enabled?(org, feature), do: Map.get(org.features || %{}, feature, false)

  defp next_states("draft"), do: ~w(scheduled canceled)
  defp next_states("scheduled"), do: ~w(live canceled did_not_occur)
  defp next_states("live"), do: ~w(ended)
  defp next_states(_), do: []
end
