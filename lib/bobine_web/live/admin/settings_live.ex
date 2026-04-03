defmodule BobineWeb.Admin.SettingsLive do
  use BobineWeb, :live_view

  alias Bobine.Billing

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

      {:error, :stripe_error, _reason} ->
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
        <section class="rounded-lg border border-base-300 p-6" data-test="stripe-connect-section">
          <h2 class="text-lg font-semibold mb-4">Payments</h2>

          <div :if={!@stripe_connected} data-test="stripe-not-connected">
            <p class="text-base-content/70 mb-4">
              Connect your Stripe account to accept viewer subscriptions and receive payments.
            </p>
            <button
              phx-click="connect_stripe"
              class="btn btn-primary"
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
            <p class="text-sm text-base-content/60 mb-4">
              Account: <code class="text-xs">{@stripe_account_id}</code>
            </p>
            <a
              href={"https://dashboard.stripe.com/#{@stripe_account_id}"}
              target="_blank"
              rel="noopener"
              class="btn btn-sm btn-ghost"
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
