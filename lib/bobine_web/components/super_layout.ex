defmodule BobineWeb.Components.SuperLayout do
  @moduledoc """
  Super admin layout component.

  Renders the sidebar and main content area for all super admin pages.
  Visually distinct from the org admin dashboard — uses a dark slate sidebar
  with a "Bobine Platform" header and a super admin badge to make it clear
  which context you're in.
  """

  use BobineWeb, :html

  attr :current_path, :string, required: true
  attr :current_user, :any, required: true
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def super_layout(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-100">
      <aside class="w-64 bg-slate-900 flex flex-col text-slate-100">
        <div class="p-4 border-b border-slate-700">
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
        <main class="flex-1 overflow-y-auto p-8">
          <.flash kind={:info} flash={@flash} />
          <.flash kind={:error} flash={@flash} />
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
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
