defmodule MarqueeWeb.Viewer.SubscribeLive do
  @moduledoc """
  Plan selection page. Lists active subscription plans for the org and
  redirects to Stripe Checkout on plan selection. Shows a message if
  Stripe Connect is not yet configured.

  Events: select_plan
  Route: /subscribe (viewer_authenticated session)
  """

  use MarqueeWeb, :live_view

  alias Marquee.Billing
  alias Marquee.Viewers
  alias MarqueeWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer
    stripe_ready = org && org.stripe_connect_onboarding_complete

    plans =
      if org do
        %{results: plans} = Billing.list_active_plans(org, per_page: 10)
        plans
      else
        []
      end

    {:ok,
     socket
     |> assign(:page_title, "Subscribe")
     |> assign(:plans, plans)
     |> assign(:viewer, viewer)
     |> assign(:stripe_ready, stripe_ready)}
  end

  @impl true
  def handle_event("select_plan", %{"plan-id" => plan_id}, socket) do
    viewer = socket.assigns.viewer
    org = socket.assigns.organization
    plan = Billing.get_plan!(org, plan_id)

    case Billing.create_viewer_checkout(org, viewer, plan) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: session.url)}

      {:error, :stripe_not_connected} ->
        {:noreply, put_flash(socket, :error, "This site is not ready to accept payments yet.")}

      {:error, :stripe_error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
    end
  end

  @impl true
  def handle_event("dev_activate", _params, socket) do
    if Application.get_env(:marquee, :dev_routes, false) do
      viewer = socket.assigns.viewer
      scope = socket.assigns[:current_scope]

      case Viewers.grant_access(scope, viewer) do
        {:ok, updated_viewer} ->
          {:noreply,
           socket
           |> assign(:viewer, updated_viewer)
           |> put_flash(:info, "Subscription activated (dev mode).")
           |> push_navigate(to: ~p"/")}

        _ ->
          {:noreply, put_flash(socket, :error, "Could not activate.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/subscribe"
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-page-content" style="max-width: 800px">
        <div class="sv-page-header" style="text-align: center">
          <h1 class="sv-page-title">Choose a plan</h1>
          <p :if={@organization} style="color: var(--sv-text-secondary); margin-top: 8px">
            Subscribe to {@organization.name}
          </p>
        </div>

        <div :if={@plans == []} class="sv-empty-state" data-test="subscribe-no-plans">
          <p class="sv-empty-state-title">No plans available yet</p>
          <p class="sv-empty-state-desc">Check back later.</p>
        </div>

        <div
          :if={@plans != []}
          class="sv-plan-grid"
          data-test="subscribe-plan-list"
        >
          <div :for={plan <- @plans} class="sv-plan-card" data-test={"plan-card-#{plan.id}"}>
            <h3 class="sv-plan-name">{plan.name}</h3>
            <p class="sv-plan-price">${format_amount(plan.amount)}</p>
            <p class="sv-plan-interval">per {plan.interval}</p>

            <p
              :if={plan.description}
              style="color: var(--sv-text-secondary); font-size: 0.875rem; margin: 8px 0"
            >
              {plan.description}
            </p>

            <ul :if={plan.features != []} style="list-style: none; padding: 0; margin: 12px 0">
              <li
                :for={feature <- plan.features}
                style="font-size: 0.8125rem; color: var(--sv-text-secondary); padding: 2px 0"
              >
                {feature}
              </li>
            </ul>

            <p
              :if={plan.trial_period_days && plan.trial_period_days > 0}
              style="font-size: 0.8125rem; color: var(--sv-accent); margin: 8px 0"
            >
              {plan.trial_period_days}-day free trial
            </p>

            <button
              phx-click="select_plan"
              phx-value-plan-id={plan.id}
              class="sv-btn sv-btn-accent"
              style="width: 100%"
              data-test={"subscribe-btn-#{plan.id}"}
            >
              {if plan.trial_period_days && plan.trial_period_days > 0,
                do: "Start free trial",
                else: "Subscribe"}
            </button>
          </div>
        </div>

        <div
          :if={Application.get_env(:marquee, :dev_routes, false)}
          style="margin-top: 32px; padding: 16px; border: 2px dashed var(--sv-accent); border-radius: var(--sv-radius-lg); text-align: center"
        >
          <p style="color: var(--sv-accent); font-size: 0.875rem; font-weight: 500">Dev Mode</p>
          <p style="font-size: 0.8125rem; color: var(--sv-text-secondary); margin-top: 4px">
            Activate subscription instantly for testing.
          </p>
          <button
            phx-click="dev_activate"
            class="sv-btn sv-btn-accent"
            style="margin-top: 12px"
            data-test="subscribe-dev-activate-btn"
          >
            Activate (dev only)
          </button>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end

  defp format_amount(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remaining_cents = rem(cents, 100)
    "#{dollars}.#{String.pad_leading(Integer.to_string(remaining_cents), 2, "0")}"
  end

  defp format_amount(_), do: "0.00"
end
