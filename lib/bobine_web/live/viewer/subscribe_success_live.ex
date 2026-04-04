defmodule BobineWeb.Viewer.SubscribeSuccessLive do
  @moduledoc """
  Post-checkout success page. Shows a welcome message after Stripe
  Checkout completes. Static — no events.

  Route: /subscribe/success (viewer_authenticated session)
  """

  use BobineWeb, :live_view

  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Subscription Confirmed")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/subscribe/success"
      theme={@theme}
      flash={@flash}
    >
      <div
        class="sv-page-content"
        style="max-width: 600px; text-align: center"
        data-test="subscribe-success"
      >
        <div style="margin-bottom: 24px">
          <span style="font-size: 3rem">&#127881;</span>
        </div>
        <h1 class="sv-page-title" style="margin-bottom: 12px">Welcome!</h1>
        <p style="color: var(--sv-text-secondary); margin-bottom: 24px">
          Your subscription is active. You now have full access to {@organization.name}.
        </p>
        <a href="/" class="sv-btn sv-btn-accent" data-test="start-watching-link">
          Start watching
        </a>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
