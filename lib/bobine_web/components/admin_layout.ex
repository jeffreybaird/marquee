defmodule BobineWeb.Components.AdminLayout do
  @moduledoc """
  Admin dashboard layout component.

  Renders a responsive sidebar navigation and main content area.
  On mobile, the sidebar slides in via JS commands.
  """

  use BobineWeb, :html

  attr :current_path, :string, required: true
  attr :organization, :any, required: true
  attr :current_user, :any, required: true
  attr :impersonating, :boolean, default: false
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def admin_layout(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-bg font-body text-text-primary">
      <div
        :if={@impersonating}
        class="bg-error text-accent-text font-ui text-sm px-4 py-2 flex items-center justify-between"
        data-test="impersonation-banner"
      >
        <span>
          Viewing <strong>{@organization.name}</strong> as super admin
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

      <%!-- Mobile header --%>
      <div class="lg:hidden flex items-center justify-between px-4 py-3 border-b border-border">
        <p
          :if={!@impersonating}
          class="font-display font-semibold text-text-primary truncate"
          data-test="org-name-mobile"
        >
          {@organization.name}
        </p>
        <p :if={@impersonating} class="font-display font-semibold text-text-primary truncate text-sm">
          Impersonating
        </p>
        <button
          phx-click={show_sidebar()}
          class="rounded-md p-1.5 text-text-secondary hover:bg-elevated hover:text-text-primary"
          aria-label="Open menu"
        >
          <.icon name="hero-bars-3" class="size-5" />
        </button>
      </div>

      <div class="flex flex-1 overflow-hidden">
        <%!-- Mobile overlay --%>
        <div
          id="admin-overlay"
          phx-click={hide_sidebar()}
          class="fixed inset-0 bg-bg/60 z-30 hidden lg:!hidden"
        >
        </div>

        <%!-- Sidebar --%>
        <aside
          id="admin-sidebar"
          class="fixed inset-y-0 left-0 z-40 w-64 bg-surface flex flex-col border-r border-border -translate-x-full transition-transform duration-200 ease-in-out lg:static lg:translate-x-0"
        >
          <div class="p-4 border-b border-border flex items-center justify-between">
            <div class="min-w-0">
              <p
                :if={!@impersonating}
                class="font-display font-semibold text-text-primary truncate"
                data-test="org-name"
              >
                {@organization.name}
              </p>
              <p
                :if={@impersonating}
                class="font-display font-semibold text-text-primary truncate text-sm"
              >
                Impersonating
              </p>
              <p class="text-xs text-text-muted truncate mt-1">{@current_user.email}</p>
            </div>
            <button
              phx-click={hide_sidebar()}
              class="rounded-md p-1.5 text-text-secondary hover:bg-elevated hover:text-text-primary lg:hidden"
              aria-label="Close menu"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
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
              href={~p"/admin/collections"}
              label="Collections"
              current_path={@current_path}
              data_test="admin-nav-collections"
            />
            <.nav_link
              href={~p"/admin/series"}
              label="Series"
              current_path={@current_path}
              data_test="admin-nav-series"
            />
            <.nav_link
              href={~p"/admin/tags"}
              label="Tags"
              current_path={@current_path}
              data_test="admin-nav-tags"
            />
            <.nav_link
              href={~p"/admin/catalog"}
              label="Catalog"
              current_path={@current_path}
              data_test="admin-nav-catalog"
            />
            <.nav_link
              href={~p"/admin/landing"}
              label="Landing Page"
              current_path={@current_path}
              data_test="admin-nav-landing"
            />
            <.nav_link
              href={~p"/admin/analytics"}
              label="Analytics"
              current_path={@current_path}
              data_test="admin-nav-analytics"
            />
            <.nav_link
              href={~p"/admin/appearance"}
              label="Appearance"
              current_path={@current_path}
              data_test="admin-nav-appearance"
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
            <.nav_link
              href={~p"/admin/settings/billing"}
              label="Billing"
              current_path={@current_path}
              data_test="admin-nav-billing"
            />
            <.nav_link
              href={~p"/admin/audit-log"}
              label="Audit Log"
              current_path={@current_path}
              data_test="admin-nav-audit-log"
            />
          </nav>

          <div class="p-3 border-t border-border">
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="block px-3 py-2 rounded-md font-ui text-sm font-medium text-text-secondary hover:bg-elevated hover:text-text-primary transition-colors"
              data-test="admin-nav-logout"
            >
              Log out
            </.link>
          </div>
        </aside>

        <div class="flex-1 flex flex-col overflow-hidden bg-bg">
          <main class="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">
            {render_slot(@inner_block)}
          </main>
          <div class="flex justify-end px-4 py-2 border-t border-border">
            <Layouts.theme_toggle />
          </div>
        </div>
      </div>

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  defp show_sidebar do
    %JS{}
    |> JS.remove_class("hidden", to: "#admin-overlay")
    |> JS.remove_class("-translate-x-full", to: "#admin-sidebar")
    |> JS.add_class("translate-x-0", to: "#admin-sidebar")
  end

  defp hide_sidebar do
    %JS{}
    |> JS.add_class("hidden", to: "#admin-overlay")
    |> JS.remove_class("translate-x-0", to: "#admin-sidebar")
    |> JS.add_class("-translate-x-full", to: "#admin-sidebar")
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
      aria-current={if @current_path == @href, do: "page"}
      data-test={@data_test}
    >
      {@label}
    </.link>
    """
  end

  defp nav_link_class(current_path, href) do
    base = "block px-3 py-2 rounded-md font-ui text-sm font-medium transition-colors"

    if current_path == href do
      "#{base} bg-accent text-accent-text"
    else
      "#{base} text-text-secondary hover:bg-elevated hover:text-text-primary"
    end
  end
end
