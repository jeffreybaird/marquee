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
    assigns = assign(assigns, :admin_accent_style, admin_accent_style(assigns.organization))

    ~H"""
    <style :if={@admin_accent_style}><%= Phoenix.HTML.raw(@admin_accent_style) %></style>
    <div class="flex flex-col h-screen bg-admin-bg font-body text-admin-text-primary">
      <div
        :if={@impersonating}
        class="bg-error text-admin-accent-text font-ui text-sm px-4 py-2 flex items-center justify-between"
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
      <div class="lg:hidden flex items-center justify-between px-4 py-3 border-b border-admin-border">
        <p
          :if={!@impersonating}
          class="font-display font-semibold text-admin-text-primary truncate"
          data-test="org-name-mobile"
        >
          {@organization.name}
        </p>
        <p :if={@impersonating} class="font-display font-semibold text-admin-text-primary truncate text-sm">
          Impersonating
        </p>
        <button
          phx-click={show_sidebar()}
          class="rounded-md p-1.5 text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary"
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
          class="fixed inset-0 bg-admin-bg/60 z-30 hidden lg:!hidden"
        >
        </div>

        <%!-- Sidebar --%>
        <aside
          id="admin-sidebar"
          class="fixed inset-y-0 left-0 z-40 w-64 bg-admin-surface flex flex-col border-r border-admin-border -translate-x-full transition-transform duration-200 ease-in-out lg:static lg:translate-x-0"
        >
          <div class="p-4 border-b border-admin-border flex items-center justify-between">
            <div class="min-w-0">
              <p
                :if={!@impersonating}
                class="font-display font-semibold text-admin-text-primary truncate"
                data-test="org-name"
              >
                {@organization.name}
              </p>
              <p
                :if={@impersonating}
                class="font-display font-semibold text-admin-text-primary truncate text-sm"
              >
                Impersonating
              </p>
              <p class="text-xs text-admin-text-muted truncate mt-1">{@current_user.email}</p>
            </div>
            <button
              phx-click={hide_sidebar()}
              class="rounded-md p-1.5 text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary lg:hidden"
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

          <div class="p-3 border-t border-admin-border">
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="block px-3 py-2 rounded-md font-ui text-sm font-medium text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary transition-colors"
              data-test="admin-nav-logout"
            >
              Log out
            </.link>
          </div>
        </aside>

        <div class="flex-1 flex flex-col overflow-hidden bg-admin-bg">
          <main class="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">
            {render_slot(@inner_block)}
          </main>
          <div class="flex justify-end px-4 py-2 border-t border-admin-border">
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

  # Per-org admin accent override. Only the accent scale is tenant-tunable
  # for the admin chrome (surface + text tokens stay pinned to Bobine brand
  # for readability). When set, we emit a scoped `<style>` that overrides
  # `--color-admin-accent*` for this tenant's admin session. Hover/active
  # variants are derived in-place via `color-mix` so operators only need
  # to pick the base color.
  defp admin_accent_style(%{admin_accent_color: color}) when is_binary(color) and color != "" do
    """
    :root {
      --color-admin-accent: #{color};
      --color-admin-accent-hover: color-mix(in oklch, #{color} 85%, white);
      --color-admin-accent-active: color-mix(in oklch, #{color} 85%, black);
      --color-admin-accent-subtle: color-mix(in oklch, #{color} 20%, var(--color-admin-surface));
    }
    """
  end

  defp admin_accent_style(_), do: nil

  defp nav_link_class(current_path, href) do
    base = "block px-3 py-2 rounded-md font-ui text-sm font-medium transition-colors"

    if current_path == href do
      "#{base} bg-admin-accent text-admin-accent-text"
    else
      "#{base} text-admin-text-secondary hover:bg-admin-elevated hover:text-admin-text-primary"
    end
  end
end
