defmodule BobineWeb.Admin.BrandingLive do
  @moduledoc """
  Theme editor for the viewer-facing site. Color pickers with live
  preview. Saves to the org's Branding.Theme and invalidates cache.

  Events: validate (live preview), save
  Route: /admin/branding
  """

  use BobineWeb, :live_view

  alias Bobine.Branding
  alias Bobine.Branding.Theme

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    theme = Branding.get_theme_or_default(org)

    changeset = Branding.change_theme(theme)

    {:ok,
     socket
     |> assign(:page_title, "Branding")
     |> assign(:theme, theme)
     |> assign(:preview_theme, theme)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"theme" => params}, socket) do
    theme = socket.assigns.theme
    changeset = Branding.change_theme(theme, params)

    preview = apply_preview(theme, params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:preview_theme, preview)}
  end

  @impl true
  def handle_event("save", %{"theme" => params}, socket) do
    org = socket.assigns.organization
    theme = socket.assigns.theme

    result =
      if theme.id do
        Branding.update_theme(theme, params)
      else
        Branding.create_theme(Map.put(params, "organization_id", org.id))
      end

    case result do
      {:ok, updated_theme} ->
        {:noreply,
         socket
         |> assign(:theme, updated_theme)
         |> assign(:preview_theme, updated_theme)
         |> assign(:form, to_form(Branding.change_theme(updated_theme)))
         |> put_flash(:info, "Theme published.")}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp apply_preview(%Theme{} = base, params) do
    Enum.reduce(params, base, fn {key, value}, acc ->
      atom_key =
        try do
          String.to_existing_atom(key)
        rescue
          ArgumentError -> nil
        end

      if atom_key && Map.has_key?(acc, atom_key) && value != "" do
        Map.put(acc, atom_key, value)
      else
        acc
      end
    end)
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
      <.header>
        Branding
        <:subtitle>Customize your viewer-facing theme</:subtitle>
      </.header>

      <div class="sv-preview-container mt-6" data-test="branding-preview">
        <%!-- Editor panel --%>
        <div class="sv-preview-editor">
          <.form for={@form} phx-change="validate" phx-submit="save">
            <div class="space-y-4">
              <h3 class="text-lg font-medium">Colors</h3>

              <.color_input form={@form} field={:brand_primary} label="Brand Primary" />
              <.color_input form={@form} field={:brand_primary_hover} label="Brand Primary Hover" />
              <.color_input form={@form} field={:background} label="Background" />
              <.color_input form={@form} field={:surface} label="Surface" />
              <.color_input form={@form} field={:elevated} label="Elevated" />
              <.color_input form={@form} field={:text_primary} label="Text Primary" />
              <.color_input form={@form} field={:text_secondary} label="Text Secondary" />
              <.color_input form={@form} field={:text_on_accent} label="Text on Accent" />
              <.color_input form={@form} field={:card_background} label="Card Background" />
              <.color_input form={@form} field={:nav_background} label="Nav Background" />

              <h3 class="text-lg font-medium mt-6">Typography</h3>

              <.input field={@form[:font_heading]} type="text" label="Heading Font" />
              <.input field={@form[:font_body]} type="text" label="Body Font" />

              <h3 class="text-lg font-medium mt-6">Assets</h3>
              <.input field={@form[:logo_url]} type="text" label="Logo URL" />
              <.input field={@form[:favicon_url]} type="text" label="Favicon URL" />

              <div class="mt-6">
                <.button type="submit" data-test="branding-publish-btn">
                  Publish theme
                </.button>
              </div>
            </div>
          </.form>
        </div>

        <%!-- Preview panel --%>
        <div class="sv-preview-frame" data-test="branding-preview-frame">
          <div
            class="sv-root"
            style={Theme.build_css_vars(@preview_theme)}
          >
            <%!-- Mini nav --%>
            <div style="padding: 12px 24px; background: var(--sv-nav-bg); display: flex; align-items: center; justify-content: space-between">
              <span style="font-family: var(--sv-font-heading); font-weight: 600; color: var(--sv-text-primary)">
                {@organization.name}
              </span>
              <span style="font-size: 0.75rem; color: var(--sv-text-secondary)">
                Home &nbsp; Browse &nbsp; Collections
              </span>
            </div>

            <%!-- Mini hero --%>
            <div style="height: 180px; background: linear-gradient(135deg, var(--sv-bg-secondary), var(--sv-bg-primary)); display: flex; align-items: flex-end; padding: 24px">
              <div>
                <div style="font-size: 0.625rem; text-transform: uppercase; letter-spacing: 0.1em; color: var(--sv-text-secondary); margin-bottom: 4px">
                  Featured
                </div>
                <div style="font-family: var(--sv-font-heading); font-size: 1.25rem; font-weight: 500; color: var(--sv-text-primary)">
                  Sample Title
                </div>
                <div style="margin-top: 8px">
                  <span style="display: inline-block; padding: 6px 16px; background: var(--sv-accent); color: var(--sv-text-on-accent); border-radius: 4px; font-size: 0.75rem; font-weight: 500">
                    Watch now
                  </span>
                </div>
              </div>
            </div>

            <%!-- Mini content rows --%>
            <div style="padding: 16px 24px">
              <div style="font-family: var(--sv-font-heading); font-size: 0.875rem; font-weight: 500; color: var(--sv-text-primary); margin-bottom: 8px">
                Trending Now
              </div>
              <div style="display: flex; gap: 8px">
                <div
                  :for={_i <- 1..4}
                  style="flex-shrink: 0; width: 100px; background: var(--sv-card-bg); border-radius: 4px; overflow: hidden"
                >
                  <div style="aspect-ratio: 16/9; background: var(--sv-bg-elevated)" />
                  <div style="padding: 6px">
                    <div style="height: 8px; width: 80%; background: var(--sv-bg-elevated); border-radius: 2px" />
                  </div>
                </div>
              </div>
            </div>

            <div style="padding: 8px 24px 24px">
              <div style="font-family: var(--sv-font-heading); font-size: 0.875rem; font-weight: 500; color: var(--sv-text-primary); margin-bottom: 8px">
                New Releases
              </div>
              <div style="display: flex; gap: 8px">
                <div
                  :for={_i <- 1..4}
                  style="flex-shrink: 0; width: 100px; background: var(--sv-card-bg); border-radius: 4px; overflow: hidden"
                >
                  <div style="aspect-ratio: 16/9; background: var(--sv-bg-elevated)" />
                  <div style="padding: 6px">
                    <div style="height: 8px; width: 60%; background: var(--sv-bg-elevated); border-radius: 2px" />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  attr :form, :map, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  defp color_input(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <label class="text-sm font-medium text-base-content min-w-[140px]">{@label}</label>
      <input
        type="color"
        name={"theme[#{@field}]"}
        value={Phoenix.HTML.Form.input_value(@form, @field) || "#000000"}
        class="h-8 w-8 cursor-pointer rounded border border-base-300"
      />
      <input
        type="text"
        name={"theme[#{@field}]"}
        value={Phoenix.HTML.Form.input_value(@form, @field)}
        class="input input-bordered input-sm w-36"
        placeholder="#000000"
      />
    </div>
    """
  end
end
