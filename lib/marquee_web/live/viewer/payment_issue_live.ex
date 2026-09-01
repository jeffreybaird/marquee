defmodule MarqueeWeb.Viewer.PaymentIssueLive do
  @moduledoc """
  Payment issue page shown to viewers with past-due subscriptions.
  Redirects to Stripe billing portal to update payment method.
  Redirects to home if subscription is not actually past-due.

  Events: update_payment
  Route: /account/payment-issue (viewer_authenticated session)
  """

  use MarqueeWeb, :live_view

  alias Marquee.Billing
  alias MarqueeWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    viewer = socket.assigns.current_viewer

    if viewer.subscription_status != "past_due" do
      {:ok, redirect(socket, to: ~p"/")}
    else
      {:ok, assign(socket, :page_title, "Payment Issue")}
    end
  end

  @impl true
  def handle_event("update_payment", _params, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    case Billing.create_viewer_portal_session(org, viewer) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: session.url)}

      {:error, :stripe_not_connected} ->
        {:noreply, put_flash(socket, :error, "Payment management is not available.")}

      {:error, :stripe_error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/account/payment-issue"
      theme={@theme}
      flash={@flash}
    >
      <div
        class="sv-page-content"
        style="max-width: 600px; text-align: center"
        data-test="payment-issue-page"
      >
        <div style="margin-bottom: 24px">
          <span style="font-size: 3rem; color: #ff5050">&#9888;</span>
        </div>
        <h1 class="sv-page-title" style="margin-bottom: 12px">Payment issue</h1>
        <p style="color: var(--sv-text-secondary); margin-bottom: 8px">
          Your last payment didn't go through.
        </p>
        <p style="color: var(--sv-text-secondary); margin-bottom: 24px">
          Update your payment method to keep watching {@organization.name}.
        </p>
        <button
          phx-click="update_payment"
          class="sv-btn sv-btn-accent"
          data-test="update-payment-btn"
        >
          Update payment method
        </button>
        <div style="margin-top: 16px">
          <a href="/subscribe" class="sv-link" style="font-size: 0.875rem">View plans</a>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
