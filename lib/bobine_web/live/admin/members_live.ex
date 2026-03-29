defmodule BobineWeb.Admin.MembersLive do
  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Members")}
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
      <.header>Members</.header>
      <p class="mt-4 text-base-content/70">Team member management coming soon.</p>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end
end
