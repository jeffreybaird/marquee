defmodule MarqueeWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard landing page.

  Redirects to onboarding while first-run setup is pending. Otherwise shows
  setup nudges (dismissable, per operator), at-a-glance KPIs, recent uploads
  with Mux processing status, recent viewer signups, and a top-content
  summary. Deep analytics live at `/admin/analytics`.

  Route: /admin
  """

  use MarqueeWeb, :live_view

  alias Marquee.Accounts
  alias Marquee.Analytics
  alias Marquee.Billing
  alias Marquee.Branding
  alias Marquee.Catalog
  alias Marquee.Content
  alias Marquee.Viewers
  alias MarqueeWeb.Admin.DashboardNudges
  alias MarqueeWeb.Admin.OnboardingLive

  @period "30"

  @impl true
  def mount(_params, _session, socket) do
    if OnboardingLive.pending?(socket.assigns[:organization], socket.assigns[:current_membership]) do
      {:ok, push_navigate(socket, to: ~p"/admin/onboarding")}
    else
      org = socket.assigns.organization
      user = socket.assigns.current_user

      socket =
        socket
        |> assign(page_title: "Dashboard")
        |> assign(
          show_tour: not Accounts.admin_tour_completed?(socket.assigns[:current_membership])
        )
        |> load_dashboard(org, user)

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("restart_tour", _params, socket) do
    {:noreply, push_event(socket, "start-tour", %{})}
  end

  @impl true
  def handle_event("tour_completed", _params, socket) do
    Accounts.complete_admin_tour(socket.assigns[:current_membership])
    {:noreply, assign(socket, :show_tour, false)}
  end

  @impl true
  def handle_event("dismiss_nudge", %{"key" => key}, socket) do
    org = socket.assigns.organization
    user = socket.assigns.current_user

    case Accounts.dismiss_nudge(user, org, key) do
      {:ok, _dismissal} ->
        {:noreply, update(socket, :nudges, &Enum.reject(&1, fn n -> n.key == key end))}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not dismiss that card. Please try again.")}
    end
  end

  defp load_dashboard(socket, org, user) do
    overview = Analytics.get_overview_cards(org, @period)
    dismissed = Accounts.list_dismissed_nudge_keys(user, org)

    conditions = %{
      stripe_connected: Billing.ensure_stripe_connected(org) == :ok,
      has_plans: Billing.list_active_plans(org, per_page: 1).total > 0,
      has_theme: not is_nil(Branding.get_theme_by_org(org)),
      has_catalog_rows: Catalog.count_rows(org) > 0
    }

    socket
    |> assign(overview: overview)
    |> assign(published_count: Content.count_published_videos(org))
    |> assign(recent_videos: Content.list_videos(org, per_page: 5).results)
    |> assign(recent_viewers: Viewers.list_viewers(org, per_page: 5).results)
    |> assign(top_content: Analytics.list_content_performance(org, @period, per_page: 5).results)
    |> assign(nudges: DashboardNudges.active(conditions, dismissed))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      trial_status={@trial_status}
      sample_content_present?={@sample_content_present?}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <div class="space-y-8">
        <div
          id="admin-guided-tour"
          phx-hook="GuidedTour"
          data-auto-start={to_string(@show_tour)}
          data-tour-brand={@organization.name}
          class="hidden"
        >
        </div>

        <.header>
          Dashboard
          <:actions>
            <button
              type="button"
              phx-click="restart_tour"
              class="text-sm font-medium text-admin-muted hover:text-admin-fg hover:underline"
              data-test="restart-tour"
            >
              Take a tour
            </button>
          </:actions>
        </.header>

        <%!-- Setup nudges (dismissable, top of page) --%>
        <section
          :if={@nudges != []}
          aria-label="Setup tasks"
          class="space-y-3"
          data-test="dashboard-nudges"
        >
          <.nudge_card :for={nudge <- @nudges} nudge={nudge} />
        </section>

        <%!-- KPI cards --%>
        <section aria-label="Overview" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <.kpi_card
            label="Active Subscribers"
            value={@overview.active_subscribers}
            data_test="kpi-active-subscribers"
          />
          <.kpi_card label="MRR" value={"$#{format_cents(@overview.mrr_cents)}"} data_test="kpi-mrr" />
          <.kpi_card
            label="Total Views (30d)"
            value={@overview.total_views}
            data_test="kpi-total-views"
          />
          <.kpi_card
            label="Published Videos"
            value={@published_count}
            data_test="kpi-published-videos"
          />
        </section>

        <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <%!-- Recent uploads --%>
          <section aria-label="Recent uploads" data-test="recent-uploads">
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Recent Uploads</h2>
              <.link navigate="/admin/content" class="text-sm text-admin-muted hover:underline">
                View all
              </.link>
            </div>

            <div
              :if={@recent_videos == []}
              class="text-sm text-admin-muted"
              data-test="recent-uploads-empty"
            >
              No videos yet. <.link navigate="/admin/content" class="underline">Upload your first video</.link>.
            </div>

            <ul
              :if={@recent_videos != []}
              class="divide-y divide-admin-border rounded-xl border border-admin-border"
            >
              <li :for={video <- @recent_videos} class="flex items-center justify-between gap-3 p-3">
                <span class="truncate">{video.title}</span>
                <.mux_status_badge status={video.mux_status} />
              </li>
            </ul>
          </section>

          <%!-- Recent signups --%>
          <section aria-label="Recent viewer signups" data-test="recent-signups">
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-semibold">Recent Signups</h2>
              <.link navigate="/admin/members" class="text-sm text-admin-muted hover:underline">
                View all
              </.link>
            </div>

            <div
              :if={@recent_viewers == []}
              class="text-sm text-admin-muted"
              data-test="recent-signups-empty"
            >
              No viewers yet.
            </div>

            <ul
              :if={@recent_viewers != []}
              class="divide-y divide-admin-border rounded-xl border border-admin-border"
            >
              <li :for={viewer <- @recent_viewers} class="flex items-center justify-between gap-3 p-3">
                <span class="truncate">{viewer.display_name || viewer.email}</span>
                <span class="text-xs text-admin-muted">{viewer.subscription_status}</span>
              </li>
            </ul>
          </section>
        </div>

        <%!-- Top content --%>
        <section aria-label="Top content" data-test="top-content">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-semibold">Top Content (30d)</h2>
            <.link navigate="/admin/analytics" class="text-sm text-admin-muted hover:underline">
              Full analytics
            </.link>
          </div>

          <div :if={@top_content == []} class="text-sm text-admin-muted" data-test="top-content-empty">
            No viewing data yet.
          </div>

          <ul
            :if={@top_content != []}
            class="divide-y divide-admin-border rounded-xl border border-admin-border"
          >
            <li :for={row <- @top_content} class="flex items-center justify-between gap-3 p-3">
              <.link
                navigate={"/admin/analytics/videos/#{row.video_id}"}
                class="truncate hover:underline"
              >
                {row.title}
              </.link>
              <span class="text-xs text-admin-muted whitespace-nowrap">
                {row.unique_viewers} viewers
              </span>
            </li>
          </ul>
        </section>
      </div>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :nudge, :map, required: true

  defp nudge_card(assigns) do
    ~H"""
    <div
      class="flex items-start justify-between gap-4 rounded-xl border border-admin-border bg-admin-bg p-4"
      data-test={"nudge-#{@nudge.key}"}
    >
      <div class="min-w-0">
        <p class="font-semibold">{@nudge.title}</p>
        <p class="text-sm text-admin-muted mt-1">{@nudge.body}</p>
        <.link
          navigate={@nudge.cta_path}
          class="text-sm font-medium text-admin-accent hover:underline mt-2 inline-block"
        >
          {@nudge.cta_label}
        </.link>
      </div>
      <button
        type="button"
        phx-click="dismiss_nudge"
        phx-value-key={@nudge.key}
        class="shrink-0 rounded p-1 text-admin-muted hover:text-admin-fg focus-visible:outline-2 focus-visible:outline-admin-accent"
        aria-label={"Dismiss: #{@nudge.title}"}
        data-test={"dismiss-nudge-#{@nudge.key}"}
      >
        <.icon name="hero-x-mark" class="size-5" />
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :data_test, :string, required: true

  defp kpi_card(assigns) do
    ~H"""
    <div class="bg-admin-bg rounded-xl p-5" data-test={@data_test}>
      <p class="text-sm text-admin-muted">{@label}</p>
      <p class="text-2xl font-bold mt-1">{@value}</p>
    </div>
    """
  end

  attr :status, :string, required: true

  defp mux_status_badge(assigns) do
    ~H"""
    <span
      class={["text-xs font-medium px-2 py-0.5 rounded-full whitespace-nowrap", badge_class(@status)]}
      data-test="mux-status-badge"
    >
      {status_label(@status)}
    </span>
    """
  end

  defp badge_class("ready"), do: "bg-green-500/15 text-green-400"
  defp badge_class("errored"), do: "bg-red-500/15 text-red-400"
  defp badge_class(_), do: "bg-yellow-500/15 text-yellow-400"

  defp status_label("ready"), do: "Ready"
  defp status_label("errored"), do: "Error"
  defp status_label("preparing"), do: "Processing"
  defp status_label("waiting"), do: "Waiting"
  defp status_label(other), do: other

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)
    "#{dollars}.#{String.pad_leading("#{remainder}", 2, "0")}"
  end

  defp format_cents(_), do: "0.00"
end
