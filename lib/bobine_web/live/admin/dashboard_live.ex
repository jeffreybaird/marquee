defmodule BobineWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard landing page. Placeholder — will show org-level stats.

  Route: /admin
  """

  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dashboard")}
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
      <.header>Dashboard</.header>
      <p class="mt-4 text-base-content/70">Welcome to your dashboard.</p>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end
end
