defmodule BobineWeb.Components.SuperLayout do
  @moduledoc """
  Super admin layout component.

  Responsive sidebar with dark slate styling. On mobile, the sidebar
  slides in via JS commands.
  """

  use BobineWeb, :html

  attr :current_path, :string, required: true
  attr :current_user, :any, required: true
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def super_layout(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-base-100">
      <%!-- Mobile header --%>
      <div class="lg:hidden flex items-center justify-between px-4 py-3 bg-slate-900 text-white">
        <p class="font-bold text-sm tracking-wide uppercase">Bobine Platform</p>
        <button
          phx-click={show_sidebar()}
          class="btn btn-ghost btn-sm btn-square text-white"
          aria-label="Open menu"
        >
          <.icon name="hero-bars-3" class="size-5" />
        </button>
      </div>

      <div class="flex flex-1 overflow-hidden">
        <%!-- Mobile overlay --%>
        <div
          id="super-overlay"
          phx-click={hide_sidebar()}
          class="fixed inset-0 bg-black/50 z-30 hidden lg:!hidden"
        >
        </div>

        <%!-- Sidebar --%>
        <aside
          id="super-sidebar"
          class="fixed inset-y-0 left-0 z-40 w-64 bg-slate-900 flex flex-col text-slate-100 -translate-x-full transition-transform duration-200 ease-in-out lg:static lg:translate-x-0"
        >
          <div class="p-4 border-b border-slate-700 flex items-center justify-between">
            <div>
              <p class="font-bold text-white text-sm tracking-wide uppercase">
                Bobine Platform
              </p>
              <span
                class="inline-block mt-1 px-2 py-0.5 text-xs font-semibold rounded bg-red-600 text-white"
                data-test="super-admin-badge"
              >
                Super Admin
              </span>
            </div>
            <button
              phx-click={hide_sidebar()}
              class="btn btn-ghost btn-sm btn-square text-white lg:hidden"
              aria-label="Close menu"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <nav class="flex-1 p-3 space-y-1 overflow-y-auto">
            <.super_nav_link
              href={~p"/super"}
              label="Dashboard"
              current_path={@current_path}
              data_test="super-nav-dashboard"
            />
            <.super_nav_link
              href={~p"/super/organizations"}
              label="Organizations"
              current_path={@current_path}
              data_test="super-nav-organizations"
            />
            <.super_nav_link
              href={~p"/super/users"}
              label="Users"
              current_path={@current_path}
              data_test="super-nav-users"
            />
          </nav>

          <div class="p-4 border-t border-slate-700">
            <p class="text-xs text-slate-400 truncate" data-test="super-current-user">
              {@current_user.email}
            </p>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="mt-1 text-xs text-slate-500 hover:text-slate-300"
            >
              Log out
            </.link>
          </div>
        </aside>

        <div class="flex-1 flex flex-col overflow-hidden">
          <main class="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">
            <.flash kind={:info} flash={@flash} />
            <.flash kind={:error} flash={@flash} />
            {render_slot(@inner_block)}
          </main>
        </div>
      </div>
    </div>
    """
  end

  defp show_sidebar do
    %JS{}
    |> JS.remove_class("hidden", to: "#super-overlay")
    |> JS.remove_class("-translate-x-full", to: "#super-sidebar")
    |> JS.add_class("translate-x-0", to: "#super-sidebar")
  end

  defp hide_sidebar do
    %JS{}
    |> JS.add_class("hidden", to: "#super-overlay")
    |> JS.remove_class("translate-x-0", to: "#super-sidebar")
    |> JS.add_class("-translate-x-full", to: "#super-sidebar")
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :current_path, :string, required: true
  attr :data_test, :string, required: true

  defp super_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={super_nav_link_class(@current_path, @href)}
      data-test={@data_test}
    >
      {@label}
    </.link>
    """
  end

  defp super_nav_link_class(current_path, href) do
    base = "block px-3 py-2 rounded-md text-sm font-medium transition-colors"

    if current_path == href do
      "#{base} bg-slate-700 text-white"
    else
      "#{base} text-slate-300 hover:bg-slate-800 hover:text-white"
    end
  end
end
