defmodule BobineWeb.Admin.SettingsLive do
  @moduledoc """
  Org settings page. Currently handles Stripe Connect onboarding
  (initiating OAuth flow). Links to billing sub-page.

  Events: connect_stripe
  Route: /admin/settings
  """

  use BobineWeb, :live_view

  alias Bobine.Billing

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:stripe_connected, org.stripe_connect_onboarding_complete)
     |> assign(:stripe_account_id, org.stripe_connect_account_id)
     |> assign(:connecting, false)}
  end

  @impl true
  def handle_event("connect_stripe", _params, socket) do
    org = socket.assigns.organization

    case Billing.initiate_connect_onboarding(org) do
      {:ok, url} ->
        {:noreply, redirect(socket, external: url)}

      {:error, :stripe_error, reason} ->
        Logger.error("Stripe Connect onboarding failed reason=#{inspect(reason)}")

        {:noreply,
         put_flash(socket, :error, "Could not start Stripe onboarding. Please try again.")}
    end
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
      <.header>Settings</.header>

      <div class="mt-8 space-y-8">
        <%!-- Payments / Stripe Connect section --%>
        <section class="rounded-lg border border-admin-border p-6" data-test="stripe-connect-section">
          <h2 class="text-lg font-semibold mb-4">Payments</h2>

          <div :if={!@stripe_connected} data-test="stripe-not-connected">
            <p class="text-admin-muted mb-4">
              Connect your Stripe account to accept viewer subscriptions and receive payments.
            </p>
            <button
              phx-click="connect_stripe"
              class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-admin-on-accent hover:brightness-110"
              data-test="connect-stripe-btn"
            >
              Connect Stripe account
            </button>
          </div>

          <div :if={@stripe_connected} data-test="stripe-connected-status">
            <div class="flex items-center gap-2 mb-2">
              <span class="inline-block w-2 h-2 rounded-full bg-success"></span>
              <span class="font-medium text-success">Stripe connected</span>
            </div>
            <p class="text-sm text-admin-muted mb-4">
              Account: <code class="text-xs">{@stripe_account_id}</code>
            </p>
            <a
              href={"https://dashboard.stripe.com/#{@stripe_account_id}"}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
              data-test="stripe-dashboard-link"
            >
              Manage in Stripe Dashboard
            </a>
          </div>
        </section>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end
end
