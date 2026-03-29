defmodule BobineWeb.Components.AdminLayout do
  @moduledoc """
  Admin dashboard layout component.

  Renders the sidebar navigation and main content area for all admin pages.
  The sidebar highlights the currently active section based on `current_path`.
  """

  use BobineWeb, :html

  attr :current_path, :string, required: true
  attr :organization, :any, required: true
  attr :current_user, :any, required: true
  attr :impersonating, :boolean, default: false
  slot :inner_block, required: true

  def admin_layout(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-base-100">
      <div
        :if={@impersonating}
        class="bg-red-600 text-white text-sm px-4 py-2 flex items-center justify-between"
        data-test="impersonation-banner"
      >
        <span>
          You are viewing <strong>{@organization.name}</strong> as a super admin.
        </span>
        <.link
          href={~p"/super/impersonate"}
          method="delete"
          class="underline font-semibold hover:no-underline"
          data-test="stop-impersonating-btn"
        >
          Stop impersonating
        </.link>
      </div>
      <div class="flex flex-1 overflow-hidden">
        <aside class="w-64 bg-base-200 flex flex-col border-r border-base-300">
          <div class="p-4 border-b border-base-300">
            <p class="font-bold text-base-content truncate" data-test="org-name">
              {@organization.name}
            </p>
            <p class="text-xs text-base-content/60 truncate mt-1">{@current_user.email}</p>
          </div>

          <nav class="flex-1 p-3 space-y-1 overflow-y-auto">
            <.nav_link
              href={~p"/admin"}
              label="Dashboard"
              current_path={@current_path}
              data_test="admin-nav-dashboard"
            />
            <.nav_link
              href={~p"/admin/content"}
              label="Content"
              current_path={@current_path}
              data_test="admin-nav-content"
            />
            <.nav_link
              href={~p"/admin/catalog"}
              label="Catalog"
              current_path={@current_path}
              data_test="admin-nav-catalog"
            />
            <.nav_link
              href={~p"/admin/analytics"}
              label="Analytics"
              current_path={@current_path}
              data_test="admin-nav-analytics"
            />
            <.nav_link
              href={~p"/admin/branding"}
              label="Branding"
              current_path={@current_path}
              data_test="admin-nav-branding"
            />
            <.nav_link
              href={~p"/admin/members"}
              label="Members"
              current_path={@current_path}
              data_test="admin-nav-members"
            />
            <.nav_link
              href={~p"/admin/webhooks"}
              label="Webhooks"
              current_path={@current_path}
              data_test="admin-nav-webhooks"
            />
            <.nav_link
              href={~p"/admin/settings"}
              label="Settings"
              current_path={@current_path}
              data_test="admin-nav-settings"
            />
          </nav>
        </aside>

        <div class="flex-1 flex flex-col overflow-hidden">
          <main class="flex-1 overflow-y-auto p-8">
            {render_slot(@inner_block)}
          </main>
        </div>
      </div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :current_path, :string, required: true
  attr :data_test, :string, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={nav_link_class(@current_path, @href)}
      data-test={@data_test}
    >
      {@label}
    </.link>
    """
  end

  defp nav_link_class(current_path, href) do
    base = "block px-3 py-2 rounded-md text-sm font-medium transition-colors"

    if current_path == href do
      "#{base} bg-primary text-primary-content"
    else
      "#{base} text-base-content hover:bg-base-300"
    end
  end
end
