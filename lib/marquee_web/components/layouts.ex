defmodule MarqueeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MarqueeWeb, :html

  alias Marquee.Accounts.Organization

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_viewer, :map, default: nil, doc: "the currently authenticated viewer"

  attr :impersonating_viewer, :boolean,
    default: false,
    doc: "whether a viewer is being impersonated"

  attr :organization, :map, default: nil, doc: "the resolved organization (tenant)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      :if={@impersonating_viewer && @current_viewer}
      class="bg-red-600 px-4 py-3 text-sm font-semibold text-white shadow-sm sm:px-6 lg:px-8"
      data-test="impersonation-banner"
    >
      <div class="mx-auto flex max-w-7xl items-center justify-between gap-4">
        <div class="flex items-center gap-2">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          <span>
            You are impersonating {viewer_identity(@current_viewer)}.
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

    <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
      <div class="flex-1">
        <a href="/" class="flex items-center gap-2 text-lg font-bold tracking-tight">
          {if @organization, do: @organization.name, else: "Marquee"}
        </a>
      </div>
      <div class="flex-none flex items-center gap-2 sm:gap-4">
        <%= cond do %>
          <% @impersonating_viewer && @current_viewer -> %>
            <span
              class="text-sm text-base-content/70 hidden sm:inline"
              data-test="viewer-header-identity"
            >
              {viewer_identity(@current_viewer)}
            </span>
            <.link href={~p"/account"} class="text-sm hover:underline hidden sm:inline">
              Account
            </.link>
            <.link
              href={~p"/viewer-session/impersonate"}
              method="delete"
              class="btn btn-ghost btn-sm"
              data-test="viewer-stop-impersonation-btn"
            >
              Stop viewing
            </.link>
          <% @current_scope && @current_scope.user -> %>
            <span class="text-sm text-base-content/70 hidden sm:inline">
              {@current_scope.user.email}
            </span>
            <.link href={~p"/users/settings"} class="text-sm hover:underline hidden sm:inline">
              Settings
            </.link>
            <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
              Log out
            </.link>
          <% @current_viewer -> %>
            <span class="text-sm text-base-content/70 hidden sm:inline">
              {@current_viewer.display_name || @current_viewer.email}
            </span>
            <.link href={~p"/account"} class="text-sm hover:underline hidden sm:inline">
              Account
            </.link>
            <.link
              href={~p"/viewer-session"}
              method="delete"
              class="btn btn-ghost btn-sm"
              data-test="viewer-logout-btn"
            >
              Log out
            </.link>
          <% @organization -> %>
            <.link href={~p"/register"} class="btn btn-ghost btn-sm">
              Register
            </.link>
            <.link href={~p"/login"} class="btn btn-primary btn-sm">
              Sign in
            </.link>
          <% true -> %>
            <.link href={~p"/users/register"} class="btn btn-ghost btn-sm">
              Register
            </.link>
            <.link href={~p"/users/log-in"} class="btn btn-primary btn-sm">
              Log in
            </.link>
        <% end %>
        <.theme_toggle />
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 sm:py-12 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      class="relative flex flex-row items-center bg-base-300/50 rounded-full p-0.5 border border-base-content/20 shadow-[inset_0_1px_3px_rgba(0,0,0,0.2),inset_0_1px_1px_rgba(0,0,0,0.1)] dark:shadow-[inset_0_1px_3px_rgba(0,0,0,0.5),inset_0_1px_1px_rgba(0,0,0,0.3)]"
      role="radiogroup"
      aria-label="Theme"
    >
      <div
        class="absolute w-1/3 h-full rounded-full bg-base-100 shadow-md ring-1 ring-base-content/10 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left] duration-200 ease-in-out"
        aria-hidden="true"
      />

      <button
        class="relative z-10 flex items-center justify-center p-2 cursor-pointer w-1/3 rounded-full"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="System theme"
        title="System theme"
      >
        <.icon
          name="hero-computer-desktop-micro"
          class="size-4 opacity-75 hover:opacity-100"
          aria-hidden="true"
        />
      </button>

      <button
        class="relative z-10 flex items-center justify-center p-2 cursor-pointer w-1/3 rounded-full"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
        title="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" aria-hidden="true" />
      </button>

      <button
        class="relative z-10 flex items-center justify-center p-2 cursor-pointer w-1/3 rounded-full"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
        title="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" aria-hidden="true" />
      </button>
    </div>
    """
  end

  defp viewer_identity(%{display_name: display_name, email: email})
       when is_binary(display_name) and display_name != "" do
    "#{display_name} (#{email})"
  end

  defp viewer_identity(%{email: email}), do: email

  @doc """
  Google Fonts link tags for the tenant's display font.

  Uses the print/onload pattern so the stylesheet is not render-blocking,
  with a `<noscript>` fallback for non-JS clients. Preconnects + preloads
  the stylesheet so swap-in has no flash of unstyled text. Returns empty
  when the tenant has not selected a custom display font (system fallback
  already present as CSS custom property default).
  """
  attr :organization, :map, default: nil
  attr :theme_preview, :map, default: nil

  def tenant_font_tags(assigns) do
    assigns = assign(assigns, :href, tenant_font_href(assigns))

    ~H"""
    <%= if @href do %>
      <.tenant_font_links href={@href} />
    <% end %>
    """
  end

  # An operator browsing with an unsaved appearance draft needs the draft's
  # display font loaded instead of the saved one.
  defp tenant_font_href(%{theme_preview: %{display_font: font}})
       when is_binary(font) and font != "",
       do: google_fonts_href(font)

  defp tenant_font_href(%{organization: %{display_font: font}})
       when is_binary(font) and font != "",
       do: google_fonts_href(font)

  defp tenant_font_href(_assigns), do: nil

  attr :href, :string, required: true

  defp tenant_font_links(assigns) do
    ~H"""
    <link rel="dns-prefetch" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link rel="preload" as="style" href={@href} />
    <link
      rel="stylesheet"
      href={@href}
      media="print"
      onload="this.media='all'; this.onload=null;"
    />
    <noscript>
      <link rel="stylesheet" href={@href} />
    </noscript>
    """
  end

  @doc """
  Inline `<style>` block scoped to the tenant's `data-tenant` attribute,
  overriding `--color-accent*` and `--font-display` at zero latency.
  Returns empty when the org has no custom branding set.
  """
  attr :organization, :map, default: nil

  def tenant_overrides(%{organization: %{slug: slug} = org} = assigns)
      when is_binary(slug) do
    case build_tenant_overrides(org) do
      [] ->
        ~H""

      overrides ->
        css = render_tenant_css(slug, overrides)
        assigns = assign(assigns, :style_tag, Phoenix.HTML.raw("<style>#{css}</style>"))

        ~H"""
        {@style_tag}
        """
    end
  end

  def tenant_overrides(assigns), do: ~H""

  defp render_tenant_css(slug, overrides) do
    body = Enum.map_join(overrides, "\n", fn {k, v} -> "  #{k}: #{v};" end)

    "html[data-tenant=\"#{escape_css_attr(slug)}\"] {\n#{body}\n}"
  end

  defp escape_css_attr(value),
    do: value |> to_string() |> String.replace("\"", "") |> String.replace("\\", "")

  defp build_tenant_overrides(org) do
    []
    |> add_override("--color-accent", Map.get(org, :accent_color_base))
    |> add_override("--color-accent-hover", Map.get(org, :accent_color_hover))
    |> add_override("--color-accent-active", Map.get(org, :accent_color_active))
    |> add_override("--color-accent-subtle", Map.get(org, :accent_color_subtle))
    |> add_display_font(Map.get(org, :display_font))
  end

  defp add_override(acc, _name, nil), do: acc
  defp add_override(acc, _name, ""), do: acc
  defp add_override(acc, name, value), do: acc ++ [{name, value}]

  defp add_display_font(acc, nil), do: acc
  defp add_display_font(acc, ""), do: acc

  defp add_display_font(acc, font) do
    acc ++
      [{"--font-display", "'#{font}', 'Georgia', 'Times New Roman', serif"}]
  end

  defp google_fonts_href(font) do
    if font in Organization.approved_display_fonts() do
      family = font |> String.replace(" ", "+")
      "https://fonts.googleapis.com/css2?family=#{family}:wght@400;500;600&display=swap"
    end
  end
end
