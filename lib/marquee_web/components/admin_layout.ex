defmodule MarqueeWeb.Components.AdminLayout do
  @moduledoc """
  Admin dashboard layout component.

  Renders a responsive sidebar navigation and main content area.
  On mobile, the sidebar slides in via JS commands.
  """

  use MarqueeWeb, :html

  attr :current_path, :string, required: true
  attr :organization, :any, required: true
  attr :current_user, :any, required: true
  attr :impersonating, :boolean, default: false
  attr :flash, :map, default: %{}
  attr :trial_status, :any, default: nil
  attr :sample_content_present?, :boolean, default: false
  slot :inner_block, required: true

  def admin_layout(assigns) do
    ~H"""
    <div data-area="admin" class="flex flex-col h-screen bg-admin-bg font-body text-admin-fg">
      <MarqueeWeb.Components.AdminDemo.bar organization={@organization} />
      <div
        :if={@impersonating}
        class="bg-error text-admin-on-accent font-ui text-sm px-4 py-2 flex items-center justify-between"
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

      <div
        :if={@trial_status && @trial_status.state == :active}
        class="bg-admin-accent-soft text-admin-fg font-ui text-sm px-4 py-2 flex items-center justify-between gap-3"
        role="status"
        aria-live="polite"
        data-test="trial-banner-active"
      >
        <span>
          Free trial — <strong>{@trial_status.days_left}</strong>
          {ngettext("day", "days", @trial_status.days_left)} left.
        </span>
        <.link
          navigate={~p"/admin/settings/billing"}
          class="underline font-semibold hover:no-underline shrink-0"
          data-test="trial-banner-billing-link"
        >
          Add payment
        </.link>
      </div>

      <div
        :if={@trial_status && @trial_status.state == :expired}
        class="bg-error text-admin-on-accent font-ui text-sm px-4 py-2 flex items-center justify-between gap-3"
        role="alert"
        aria-live="assertive"
        data-test="trial-banner-expired"
      >
        <span>
          Your free trial has ended. Add a payment method to keep publishing.
        </span>
        <.link
          navigate={~p"/admin/settings/billing"}
          class="underline font-semibold hover:no-underline shrink-0"
          data-test="trial-banner-billing-link"
        >
          Add payment
        </.link>
      </div>

      <div
        :if={@sample_content_present?}
        class="bg-admin-accent-soft text-admin-fg font-ui text-sm px-4 py-2 flex items-center justify-between gap-3"
        role="status"
        aria-live="polite"
        data-test="sample-content-banner"
      >
        <span>
          Your platform is preloaded with <strong>sample content</strong>
          so you can see how it looks. Remove it whenever you're ready.
        </span>
        <.link
          href={~p"/admin/sample-content"}
          method="delete"
          data-confirm="Remove all sample content? This cannot be undone."
          class="underline font-semibold hover:no-underline shrink-0"
          data-test="sample-content-clear"
        >
          Clear sample content
        </.link>
      </div>

      <%!-- Mobile header --%>
      <div class="lg:hidden flex items-center justify-between px-4 py-3 border-b border-admin-border">
        <p
          :if={!@impersonating}
          class="font-display font-semibold text-admin-fg truncate"
          data-test="org-name-mobile"
        >
          {@organization.name}
        </p>
        <p
          :if={@impersonating}
          class="font-display font-semibold text-admin-fg truncate text-sm"
        >
          Impersonating
        </p>
        <button
          phx-click={show_sidebar()}
          class="rounded-md p-1.5 text-admin-muted hover:bg-admin-card hover:text-admin-fg"
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
          class="fixed inset-y-0 left-0 z-40 w-64 bg-admin-card flex flex-col border-r border-admin-border -translate-x-full transition-transform duration-200 ease-in-out lg:static lg:translate-x-0"
        >
          <div class="p-4 border-b border-admin-border flex items-center justify-between">
            <div class="min-w-0">
              <p
                :if={!@impersonating}
                class="font-display font-semibold text-admin-fg truncate"
                data-test="org-name"
              >
                {@organization.name}
              </p>
              <p
                :if={@impersonating}
                class="font-display font-semibold text-admin-fg truncate text-sm"
              >
                Impersonating
              </p>
              <p class="text-xs text-admin-muted truncate mt-1">
                {if @organization.demo_kind == :admin_sandbox,
                  do: "Demo admin",
                  else: @current_user.email}
              </p>
            </div>
            <button
              phx-click={hide_sidebar()}
              class="rounded-md p-1.5 text-admin-muted hover:bg-admin-card hover:text-admin-fg lg:hidden"
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
              href={~p"/admin/podcasts"}
              label="Podcasts"
              current_path={@current_path}
              data_test="admin-nav-podcasts"
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

          <div class="p-3 border-t border-admin-border space-y-1">
            <.link
              href={viewer_site_url(@organization, @impersonating)}
              target="_blank"
              rel="noopener"
              class="flex items-center gap-2 px-3 py-2 rounded-md font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg transition-colors"
              data-test="admin-view-site"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" /> View site
              <span class="sr-only">(opens in a new tab)</span>
            </.link>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="block px-3 py-2 rounded-md font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg transition-colors"
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

  defp viewer_site_url(%{demo_kind: :admin_sandbox}, _impersonating), do: "/?preview=member"

  defp viewer_site_url(org, impersonating) do
    base =
      if not impersonating and
           (Application.get_env(:marquee, :org_resolution) == :hostname or
              Application.get_env(:marquee, :tenant_domain_provisioning, [])[:enabled] == true) and
           is_binary(Application.get_env(:marquee, :tenant_host_pattern)) do
        config = Application.get_env(:marquee, MarqueeWeb.Endpoint, [])[:url] || []

        URI.to_string(%{
          URI.new!("#{config[:scheme] || "https"}://#{config[:host]}")
          | port: config[:port]
        })
      else
        ""
      end

    MarqueeWeb.OrgURL.org_url(base <> "/?preview=member", org)
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
      "#{base} bg-admin-accent text-admin-on-accent"
    else
      "#{base} text-admin-muted hover:bg-admin-card hover:text-admin-fg"
    end
  end
end
