defmodule MarqueeWeb.Admin.WebhooksLive do
  @moduledoc """
  Webhook endpoint management. Placeholder — will allow operators to
  configure outbound webhook URLs and view delivery logs.

  Route: /admin/webhooks
  """

  use MarqueeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Webhooks")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      trial_status={@trial_status}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <.header>Webhooks</.header>
      <p class="mt-4 text-admin-muted">Webhook endpoint management coming soon.</p>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end
end
