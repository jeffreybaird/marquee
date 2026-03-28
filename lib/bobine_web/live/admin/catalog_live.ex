defmodule BobineWeb.Admin.CatalogLive do
  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Catalog")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
    >
      <.header>Catalog</.header>
      <p class="mt-4 text-base-content/70">Catalog management coming soon.</p>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end
end
