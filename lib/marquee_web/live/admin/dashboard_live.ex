defmodule MarqueeWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard landing page. Placeholder — will show org-level stats.

  Route: /admin
  """

  use MarqueeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <.header>Dashboard</.header>
      <p class="mt-4 text-admin-muted">Welcome to your dashboard.</p>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end
end
