defmodule BobineWeb.Admin.BillingLive do
  use BobineWeb, :live_view

  alias Bobine.PlatformBilling
  alias Bobine.PlatformBilling.UsageLimits
  alias Bobine.Admin

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    subscription = load_subscription(org)
    plans = load_plans()
    usage = load_usage(org)

    {:ok,
     socket
     |> assign(:page_title, "Billing")
     |> assign(:subscription, subscription)
     |> assign(:current_plan, load_current_plan(subscription))
     |> assign(:plans, plans)
     |> assign(:usage, usage)
     |> assign(:show_plan_grid, is_nil(subscription) || subscription.status == :canceled)}
  end

  @impl true
  def handle_event("subscribe", %{"plan_id" => plan_id}, socket) do
    org = socket.assigns.organization
    user = socket.assigns.current_user

    case PlatformBilling.get_platform_plan(plan_id) do
      {:ok, plan} ->
        case PlatformBilling.create_org_checkout(org, plan, user) do
          {:ok, session} ->
            {:noreply, redirect(socket, external: session.url || session["url"])}

          {:error, :plan_not_configured} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "This plan is not yet configured for checkout. Please contact support."
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not create checkout session.")}

          {:error, :stripe_error, _details} ->
            {:noreply, put_flash(socket, :error, "Could not create checkout session.")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Plan not found.")}
    end
  end

  def handle_event("manage_subscription", _params, socket) do
    org = socket.assigns.organization

    case PlatformBilling.create_org_portal_session(org) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: session.url || session["url"])}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not open billing portal.")}

      {:error, :stripe_error, _details} ->
        {:noreply, put_flash(socket, :error, "Could not open billing portal.")}
    end
  end

  def handle_event("show_change_plan", _params, socket) do
    {:noreply, assign(socket, :show_plan_grid, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <.header>Billing</.header>

      <%= if @subscription && @subscription.status == :past_due do %>
        <div
          class="mt-4 rounded-lg border border-warning bg-warning/10 p-4"
          data-test="billing-warning-banner"
          role="alert"
        >
          <p class="font-semibold text-warning">Payment overdue</p>
          <p class="mt-1 text-sm text-base-content/70">
            Your Bobine payment is overdue. Update your payment method to avoid service interruption.
          </p>
          <button
            phx-click="manage_subscription"
            class="mt-2 rounded-lg bg-warning px-4 py-2 text-sm font-medium text-warning-content"
            data-test="manage-subscription-btn"
          >
            Update payment method
          </button>
        </div>
      <% end %>

      <%= if @subscription && @subscription.status == :active do %>
        <div class="mt-6" data-test="current-subscription">
          <div class="rounded-lg border border-base-300 bg-base-200 p-6">
            <div class="flex items-center justify-between">
              <div>
                <span
                  class="inline-block rounded-full bg-success/20 px-3 py-1 text-xs font-medium text-success"
                  data-test="current-plan-badge"
                >
                  Current plan
                </span>
                <h3 class="mt-2 text-xl font-bold text-base-content">
                  {if @current_plan, do: @current_plan.name, else: "Unknown Plan"}
                </h3>
              </div>
              <div class="flex gap-2">
                <button
                  phx-click="show_change_plan"
                  class="rounded-lg border border-base-300 px-4 py-2 text-sm font-medium text-base-content hover:bg-base-300"
                  data-test="change-plan-btn"
                >
                  Change plan
                </button>
                <button
                  phx-click="manage_subscription"
                  class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content"
                  data-test="manage-subscription-btn"
                >
                  Manage subscription
                </button>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <.usage_meter
            label="Videos"
            current={@usage.videos_current}
            limit={@usage.videos_limit}
            data_test="usage-meter-videos"
          />
          <.usage_meter
            label="Monthly views"
            current={@usage.views_current}
            limit={@usage.views_limit}
            data_test="usage-meter-views"
          />
          <.usage_meter
            label="Team members"
            current={@usage.seats_current}
            limit={@usage.seats_limit}
            data_test="usage-meter-seats"
          />
        </div>
      <% end %>

      <%= if @show_plan_grid do %>
        <div class="mt-8" data-test="platform-plan-grid">
          <h2 class="text-lg font-semibold text-base-content">
            {if @subscription && @subscription.status == :active,
              do: "Change your plan",
              else: "Choose a plan"}
          </h2>
          <div class="mt-4 grid grid-cols-1 gap-4 md:grid-cols-3">
            <.plan_card
              :for={plan <- @plans}
              plan={plan}
              is_current={@current_plan && @current_plan.id == plan.id}
            />
          </div>
        </div>
      <% end %>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  attr :plan, :map, required: true
  attr :is_current, :boolean, default: false

  defp plan_card(assigns) do
    ~H"""
    <div
      class={[
        "rounded-lg border p-6",
        if(@is_current, do: "border-primary bg-primary/5", else: "border-base-300 bg-base-200"),
        if(@plan.highlight, do: "ring-2 ring-primary", else: "")
      ]}
      data-test={"platform-plan-#{@plan.slug}"}
    >
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-bold text-base-content">{@plan.name}</h3>
        <%= if @plan.highlight do %>
          <span class="rounded-full bg-primary/20 px-2 py-0.5 text-xs font-medium text-primary">
            Popular
          </span>
        <% end %>
      </div>
      <p class="mt-1 text-2xl font-bold text-base-content">
        ${format_amount(@plan.amount)}<span class="text-sm font-normal text-base-content/60">/mo</span>
      </p>
      <p :if={@plan.description} class="mt-2 text-sm text-base-content/70">{@plan.description}</p>
      <ul class="mt-4 space-y-2 text-sm text-base-content/80">
        <li>{format_limit(@plan.max_videos, "videos")}</li>
        <li>{format_limit(@plan.max_monthly_views, "views/mo")}</li>
        <li>{format_limit(@plan.max_team_seats, "team seats")}</li>
      </ul>
      <%= if @is_current do %>
        <span
          class="mt-4 block text-center text-sm font-medium text-primary"
          data-test="current-plan-badge"
        >
          Current plan
        </span>
      <% else %>
        <button
          phx-click="subscribe"
          phx-value-plan_id={@plan.id}
          class="mt-4 w-full rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content hover:bg-primary/90"
          data-test="subscribe-btn"
        >
          Subscribe
        </button>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :current, :integer, required: true
  attr :limit, :integer, default: nil
  attr :data_test, :string, required: true

  defp usage_meter(assigns) do
    percentage =
      if assigns.limit && assigns.limit > 0,
        do: min(round(assigns.current / assigns.limit * 100), 100),
        else: 0

    assigns = assign(assigns, :percentage, percentage)

    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200 p-4" data-test={@data_test}>
      <p class="text-sm text-base-content/60">{@label}</p>
      <p class="mt-1 text-lg font-bold text-base-content">
        {@current} / {if @limit, do: @limit, else: "unlimited"}
      </p>
      <%= if @limit do %>
        <div class="mt-2 h-2 w-full overflow-hidden rounded-full bg-base-300">
          <div
            class={[
              "h-full rounded-full",
              if(@percentage >= 90, do: "bg-error", else: "bg-primary")
            ]}
            style={"width: #{@percentage}%"}
          >
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_amount(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remaining = rem(cents, 100)
    "#{dollars}.#{String.pad_leading(Integer.to_string(remaining), 2, "0")}"
  end

  defp format_amount(_), do: "0.00"

  defp format_limit(nil, label), do: "Unlimited #{label}"
  defp format_limit(limit, label), do: "#{limit} #{label}"

  defp load_subscription(org) do
    case PlatformBilling.get_subscription(org) do
      {:ok, sub} -> sub
      _ -> nil
    end
  end

  defp load_current_plan(nil), do: nil

  defp load_current_plan(subscription) do
    PlatformBilling.get_platform_plan!(subscription.platform_plan_id)
  end

  defp load_plans do
    case PlatformBilling.list_platform_plans() do
      %{results: results} -> results
      results when is_list(results) -> results
    end
  end

  defp load_usage(org) do
    %{
      videos_current: Admin.video_count(org),
      videos_limit: get_plan_limit(org, :max_videos),
      views_current: 0,
      views_limit: get_plan_limit(org, :max_monthly_views),
      seats_current: Admin.member_count(org),
      seats_limit: get_plan_limit(org, :max_team_seats)
    }
  end

  defp get_plan_limit(org, field) do
    plan = UsageLimits.get_plan_for_org(org)
    Map.get(plan, field)
  end
end
