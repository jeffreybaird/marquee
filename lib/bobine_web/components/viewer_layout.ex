defmodule BobineWeb.Components.ViewerLayout do
  @moduledoc """
  Layout component for all viewer-facing pages.

  Renders the org-branded header, navigation, utilities, and main content area.
  Uses the tenant's CSS custom properties — the viewer should never see Bobine branding.
  """

  use BobineWeb, :html

  @default_nav_items [
    %{label: "Home", path: "/", id: "home"},
    %{label: "Browse", path: "/browse", id: "browse"},
    %{label: "Collections", path: "/collections", id: "collections"}
  ]

  attr :organization, :map, required: true
  attr :current_viewer, :map, default: nil
  attr :impersonating_viewer, :boolean, default: false
  attr :current_path, :string, required: true
  attr :nav_items, :list, default: nil
  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc """
  Renders the viewer-facing layout shell.

  ## Examples

      <ViewerLayout.viewer_layout organization={@organization} current_path="/" flash={@flash}>
        <h1>Content</h1>
      </ViewerLayout.viewer_layout>

  """
  def viewer_layout(assigns) do
    assigns =
      assign_new(assigns, :resolved_nav_items, fn -> assigns[:nav_items] || @default_nav_items end)

    ~H"""
    <div class="viewer-layout" data-test="viewer-layout">
      <.impersonation_banner
        :if={@impersonating_viewer && @current_viewer}
        current_viewer={@current_viewer}
      />

      <.viewer_header
        organization={@organization}
        current_viewer={@current_viewer}
        current_path={@current_path}
        nav_items={@resolved_nav_items}
      />

      <main class="viewer-main">
        {render_slot(@inner_block)}
      </main>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  attr :current_viewer, :map, required: true

  defp impersonation_banner(assigns) do
    ~H"""
    <div
      class="bg-red-600 px-4 py-3 text-sm font-semibold text-white shadow-sm sm:px-6 lg:px-8"
      data-test="impersonation-banner"
    >
      <div class="mx-auto flex max-w-7xl items-center justify-between gap-4">
        <div class="flex items-center gap-2">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          <span>
            You are impersonating {@current_viewer.display_name || @current_viewer.email}.
          </span>
        </div>
        <.link
          href={~p"/viewer-session/impersonate"}
          method="delete"
          class="shrink-0 rounded-full border border-white/50 px-3 py-1 text-xs uppercase tracking-[0.16em] text-white transition hover:bg-white hover:text-red-700"
          data-test="stop-impersonation-btn"
        >
          Stop viewing
        </.link>
      </div>
    </div>
    """
  end

  attr :organization, :map, required: true
  attr :current_viewer, :map, default: nil
  attr :current_path, :string, required: true
  attr :nav_items, :list, required: true

  defp viewer_header(assigns) do
    ~H"""
    <header class="viewer-header" data-test="viewer-header">
      <div class="viewer-header-inner">
        <%!-- Brand section (left) --%>
        <.link navigate="/" class="viewer-brand" data-test="viewer-brand-logo">
          <span class="viewer-brand-text">
            {@organization && @organization.name}
          </span>
        </.link>

        <%!-- Primary navigation (center) --%>
        <nav class="viewer-nav" data-test="viewer-nav">
          <.link
            :for={item <- @nav_items}
            navigate={item.path}
            class={["viewer-nav-item", @current_path == item.path && "active"]}
            data-test={"nav-#{item.id}"}
          >
            {item.label}
          </.link>
        </nav>

        <%!-- Utilities (right) --%>
        <div class="viewer-utilities" data-test="viewer-utilities">
          <.link
            navigate="/browse"
            data-test="search-icon"
            aria-label="Search"
            class="viewer-search-btn"
          >
            <.icon name="hero-magnifying-glass" class="size-5" />
          </.link>

          <%= if @current_viewer do %>
            <.link navigate="/account" data-test="profile-avatar" class="viewer-avatar">
              {String.first(@current_viewer.display_name || @current_viewer.email)}
            </.link>
          <% else %>
            <.link navigate="/login" data-test="sign-in-link" class="viewer-sign-in">
              Sign In
            </.link>
          <% end %>
        </div>
      </div>
    </header>
    """
  end
end
