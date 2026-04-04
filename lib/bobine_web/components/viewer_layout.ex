defmodule BobineWeb.Components.ViewerLayout do
  @moduledoc """
  Layout component for all viewer-facing pages.

  Renders the org-branded header, navigation, utilities, and main content area.
  Uses the tenant's CSS custom properties — the viewer should never see Bobine branding.
  """

  use BobineWeb, :html

  alias Bobine.Branding.Theme

  @default_nav_items [
    %{label: "Home", path: "/", id: "home", icon: "hero-home"},
    %{label: "Browse", path: "/browse", id: "browse", icon: "hero-magnifying-glass"},
    %{label: "Collections", path: "/collections", id: "collections", icon: "hero-rectangle-stack"}
  ]

  @my_stuff_nav %{label: "My Stuff", path: "/watchlist", id: "my-stuff", icon: "hero-bookmark"}

  attr :organization, :map, required: true
  attr :current_viewer, :map, default: nil
  attr :impersonating_viewer, :boolean, default: false
  attr :current_path, :string, required: true
  attr :nav_items, :list, default: nil
  attr :theme, :map, default: nil
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
      assigns
      |> assign_new(:resolved_nav_items, fn ->
        base = assigns[:nav_items] || @default_nav_items
        if assigns[:current_viewer], do: base ++ [@my_stuff_nav], else: base
      end)
      |> assign_new(:resolved_theme, fn ->
        case assigns[:theme] do
          %Theme{} = t -> t
          _ -> %Theme{}
        end
      end)
      |> assign_new(:mobile_nav_items, fn ->
        base = assigns[:nav_items] || @default_nav_items
        if assigns[:current_viewer], do: base ++ [@my_stuff_nav], else: base
      end)

    ~H"""
    <div
      class="sv-root"
      style={Theme.build_css_vars(@resolved_theme)}
      data-test="sv-root"
    >
      <.impersonation_banner
        :if={@impersonating_viewer && @current_viewer}
        current_viewer={@current_viewer}
      />

      <.viewer_header
        organization={@organization}
        current_viewer={@current_viewer}
        impersonating_viewer={@impersonating_viewer}
        current_path={@current_path}
        nav_items={@resolved_nav_items}
      />

      <main class="sv-main">
        {render_slot(@inner_block)}
      </main>

      <.mobile_nav items={@mobile_nav_items} current_path={@current_path} />

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  attr :current_viewer, :map, required: true

  defp impersonation_banner(assigns) do
    ~H"""
    <div
      class="bg-red-600 px-4 py-3 text-sm font-semibold text-white shadow-sm sm:px-6 lg:px-8"
      style="position: relative; z-index: 200"
      data-test="impersonation-banner"
    >
      <div class="mx-auto flex max-w-7xl items-center justify-between gap-4">
        <div class="flex items-center gap-2">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" aria-hidden="true" />
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
  attr :impersonating_viewer, :boolean, default: false
  attr :current_path, :string, required: true
  attr :nav_items, :list, required: true

  defp viewer_header(assigns) do
    ~H"""
    <header
      id="sv-nav"
      class="sv-nav"
      phx-hook="ViewerNav"
      data-test="sv-nav"
    >
      <div class="sv-nav-inner">
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
            aria-current={if @current_path == item.path, do: "page"}
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
            <span
              :if={@impersonating_viewer}
              class="text-sm hidden sm:inline"
              style="color: var(--sv-text-secondary)"
              data-test="viewer-header-identity"
            >
              {@current_viewer.display_name || @current_viewer.email}
            </span>
            <.link
              navigate="/account"
              data-test="profile-avatar"
              class="viewer-avatar"
              aria-label="Your account"
            >
              {String.first(@current_viewer.display_name || @current_viewer.email)}
            </.link>
            <.link
              href={~p"/viewer-session"}
              method="delete"
              data-test="viewer-sign-out"
              class="viewer-sign-out"
              aria-label="Sign out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
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

  attr :items, :list, required: true
  attr :current_path, :string, required: true

  defp mobile_nav(assigns) do
    ~H"""
    <nav class="sv-mobile-nav" aria-label="Mobile navigation" data-test="sv-mobile-nav">
      <.link
        :for={item <- @items}
        navigate={item.path}
        class={["sv-mobile-nav-item", @current_path == item.path && "active"]}
        aria-current={if @current_path == item.path, do: "page"}
        data-test={"mobile-nav-#{item.id}"}
      >
        <.icon name={item.icon} class="size-5" aria-hidden="true" />
        <span>{item.label}</span>
      </.link>
    </nav>
    """
  end
end
