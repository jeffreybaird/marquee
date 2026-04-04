defmodule BobineWeb.Admin.PlanSuccessLive do
  @moduledoc """
  Post-checkout confirmation for platform subscription. Shows the
  active plan details after Stripe Checkout completes.

  Route: /admin/settings/billing/success
  """

  use BobineWeb, :live_view

  alias Bobine.PlatformBilling

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    subscription = load_subscription(org)
    current_plan = load_current_plan(subscription)

    {:ok,
     socket
     |> assign(:page_title, "Plan Updated")
     |> assign(:current_plan, current_plan)
     |> assign(:subscription, subscription)}
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
      <.header>Plan Updated</.header>

      <div
        class="mt-6 rounded-lg border border-success bg-success/10 p-6"
        data-test="plan-success-card"
        role="status"
      >
        <div class="flex items-center gap-3">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-8 w-8 text-success"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden="true"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          <h2 class="text-lg font-semibold text-base-content">
            Your plan has been successfully updated.
          </h2>
        </div>
      </div>

      <%= if @current_plan do %>
        <div class="mt-6 rounded-lg border border-base-300 bg-base-200 p-6" data-test="plan-details">
          <div class="space-y-3">
            <div class="flex items-center justify-between">
              <span class="text-sm text-base-content/60">Plan</span>
              <span class="font-semibold text-base-content" data-test="plan-name">
                {@current_plan.name}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm text-base-content/60">Monthly price</span>
              <span class="font-semibold text-base-content" data-test="plan-amount">
                ${format_amount(@current_plan.amount)}/mo
              </span>
            </div>
            <%= if @subscription do %>
              <div class="flex items-center justify-between">
                <span class="text-sm text-base-content/60">Next billing date</span>
                <span class="font-semibold text-base-content" data-test="next-billing-date">
                  {format_date(@subscription.current_period_end)}
                </span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <div class="mt-6">
        <.link
          navigate={~p"/admin/settings/billing"}
          class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content hover:bg-primary/90"
          data-test="back-to-billing-link"
        >
          Back to billing
        </.link>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp format_amount(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remaining = rem(cents, 100)
    "#{dollars}.#{String.pad_leading(Integer.to_string(remaining), 2, "0")}"
  end

  defp format_amount(_), do: "0.00"

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %d, %Y")
  end

  defp format_date(_), do: ""

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
end
