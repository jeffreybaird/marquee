defmodule BobineWeb.Admin.BrandingLive do
  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Branding")}
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
      <.header>Branding</.header>
      <p class="mt-4 text-base-content/70">Branding and theming coming soon.</p>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end
end
