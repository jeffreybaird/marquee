defmodule BobineWeb.Admin.AppearanceLive do
  @moduledoc """
  Unified operator appearance page: preset + tenant branding + surface
  colors + typography + assets. Replaces the old split between
  /admin/branding and /admin/appearance — /admin/branding now redirects
  here.

  The preset chooser is surfaced inside a collapsible `<details>` drawer.
  For organizations that already have a configured catalog the drawer is
  closed and the "Apply" button becomes a destructive "Overwrite" action
  that soft-deletes every existing row before seeding the preset's
  defaults. For empty catalogs the drawer opens by default and the Apply
  action is non-destructive.

  Events:
    * `preview_preset`           — stage a preset preview (no save)
    * `apply_preset`             — non-destructive seed (empty catalogs)
    * `confirm_overwrite_preset` — destructive overwrite (existing rows)
    * `preview_branding`         — live-update accent + font preview
    * `save_branding`            — persist accent + display font + preset
    * `validate_theme` / `save_theme` — Theme surface colors + assets

  Route: /admin/appearance
  """

  use BobineWeb, :live_view

  import Ecto.Query

  alias Bobine.Accounts
  alias Bobine.Accounts.Organization
  alias Bobine.Branding
  alias Bobine.Branding.Theme
  alias Bobine.Catalog
  alias Bobine.Catalog.{Presets, Row}
  alias Bobine.Repo

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization

    {:ok, layout} = Catalog.get_or_create_layout(org)
    theme = Branding.get_theme_or_default(org)

    branding_form =
      org
      |> Organization.branding_changeset(%{})
      |> to_form()

    theme_form = theme |> Branding.change_theme() |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "Appearance")
     |> assign(:layout_config, layout)
     |> assign(:selected_preset, layout.preset_name)
     |> assign(:presets, Presets.list())
     |> assign(:branding_form, branding_form)
     |> assign(:accent_preview, org.accent_color_base)
     |> assign(:display_font_preview, org.display_font)
     |> assign(:display_fonts, Organization.approved_display_fonts())
     |> assign(:theme, theme)
     |> assign(:preview_theme, theme)
     |> assign(:theme_form, theme_form)
     |> assign_catalog_state(org)}
  end

  @impl true
  def handle_event("preview_preset", %{"name" => name}, socket) do
    {:noreply, assign(socket, :selected_preset, name)}
  end

  @impl true
  def handle_event("apply_preset", %{"name" => name}, socket) do
    scope = socket.assigns.current_scope
    apply_preset(socket, scope, name, destructive: false)
  end

  @impl true
  def handle_event("confirm_overwrite_preset", %{"name" => name}, socket) do
    scope = socket.assigns.current_scope
    apply_preset(socket, scope, name, destructive: true)
  end

  @impl true
  def handle_event("preview_branding", %{"organization" => params}, socket) do
    {:noreply,
     socket
     |> assign(:accent_preview, Map.get(params, "accent_color_base") || "")
     |> assign(:display_font_preview, Map.get(params, "display_font") || "")
     |> assign(
       :branding_form,
       socket.assigns.organization
       |> Organization.branding_changeset(params)
       |> to_form()
     )}
  end

  @impl true
  def handle_event("save_branding", %{"organization" => params}, socket) do
    params = maybe_derive_accent_variants(params)
    org = socket.assigns.organization

    case Accounts.update_organization_branding(org, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:organization, updated)
         |> put_flash(:info, "Branding saved.")}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, :branding_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("validate_theme", %{"theme" => params}, socket) do
    theme = socket.assigns.theme
    changeset = Branding.change_theme(theme, params)
    preview = apply_theme_preview(theme, params)

    {:noreply,
     socket
     |> assign(:theme_form, to_form(changeset))
     |> assign(:preview_theme, preview)}
  end

  @impl true
  def handle_event("save_theme", %{"theme" => params}, socket) do
    org = socket.assigns.organization
    theme = socket.assigns.theme

    result =
      if theme.id do
        Branding.update_theme(theme, params)
      else
        Branding.create_theme(Map.put(params, "organization_id", org.id))
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:theme, updated)
         |> assign(:preview_theme, updated)
         |> assign(:theme_form, to_form(Branding.change_theme(updated)))
         |> put_flash(:info, "Surface colors published.")}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, :theme_form, to_form(changeset))}
    end
  end

  defp apply_preset(socket, scope, name, destructive: destructive) do
    seed_result =
      if destructive do
        Catalog.overwrite_rows_with_preset(scope, name)
      else
        Catalog.seed_rows_from_preset_if_empty(scope, name)
      end

    case {seed_result, record_preset_choice(socket.assigns.layout_config, name)} do
      {{:error, :not_found}, _} ->
        {:noreply, put_flash(socket, :error, "Unknown preset.")}

      {_, {:ok, layout}} ->
        {:noreply,
         socket
         |> assign(:layout_config, layout)
         |> assign(:selected_preset, layout.preset_name)
         |> assign_catalog_state(socket.assigns.organization)
         |> put_flash(:info, apply_preset_message(seed_result, name))}

      {_, {:error, :validation, _}} ->
        {:noreply, put_flash(socket, :error, "Could not apply preset.")}
    end
  end

  defp record_preset_choice(layout, preset_name) do
    Catalog.update_layout(layout, %{preset_name: preset_name})
  end

  defp apply_preset_message({:ok, :seeded, rows}, name),
    do: "Applied preset #{name}. Seeded #{length(rows)} rows in Catalog."

  defp apply_preset_message({:ok, :overwritten, rows}, name),
    do: "Overwrote catalog with preset #{name}. Seeded #{length(rows)} rows."

  defp apply_preset_message({:ok, :skipped}, name),
    do: "Preset #{name} selected. Catalog already has rows — not overwritten."

  defp apply_preset_message(_other, name),
    do: "Preset #{name} selected."

  defp assign_catalog_state(socket, org) do
    row_count =
      Repo.one(
        from r in Row,
          where: r.organization_id == ^org.id and is_nil(r.deleted_at),
          select: count()
      ) || 0

    socket
    |> assign(:row_count, row_count)
    |> assign(:catalog_empty?, row_count == 0)
  end

  defp maybe_derive_accent_variants(%{"accent_color_base" => base} = params)
       when is_binary(base) and base != "" do
    params
    |> put_if_blank("accent_color_hover", shift_lightness(base, +0.06))
    |> put_if_blank("accent_color_active", shift_lightness(base, -0.06))
    |> put_if_blank("accent_color_subtle", subtle_from(base))
  end

  defp maybe_derive_accent_variants(params), do: params

  defp put_if_blank(params, key, value) do
    case Map.get(params, key) do
      v when is_binary(v) and v != "" -> params
      _ -> Map.put(params, key, value)
    end
  end

  defp shift_lightness(oklch, delta) do
    case parse_oklch(oklch) do
      {:ok, l, c, h} ->
        "oklch(#{format_number(clamp(l + delta, 0.0, 1.0))} #{format_number(c)} #{format_number(h)})"

      :error ->
        oklch
    end
  end

  defp subtle_from(oklch) do
    case parse_oklch(oklch) do
      {:ok, _l, c, h} -> "oklch(0.28 #{format_number(c / 2)} #{format_number(h)})"
      :error -> oklch
    end
  end

  defp parse_oklch(str) do
    case Regex.run(~r/oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)/, str) do
      [_, l, c, h] ->
        {:ok, String.to_float(ensure_dot(l)), String.to_float(ensure_dot(c)),
         String.to_float(ensure_dot(h))}

      _ ->
        :error
    end
  end

  defp ensure_dot(s), do: if(String.contains?(s, "."), do: s, else: s <> ".0")
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 3)
  defp format_number(n), do: to_string(n)

  defp apply_theme_preview(%Theme{} = base, params) do
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
        Appearance
        <:subtitle>Preset, accent, display font, and surface colors</:subtitle>
      </.header>

      <details
        class="mt-6 rounded-lg border border-base-300"
        data-test="preset-drawer"
        open={@catalog_empty?}
      >
        <summary class="cursor-pointer px-4 py-3 text-sm font-medium">
          <span>Preset chooser</span>
          <span :if={!@catalog_empty?} class="ml-2 text-xs opacity-60">
            (advanced — overwrites your catalog)
          </span>
        </summary>

        <div class="border-t border-base-300 p-4" data-test="preset-picker">
          <div
            :if={!@catalog_empty?}
            class="mb-4 rounded-md border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-200"
            data-test="preset-destructive-warning"
            role="alert"
          >
            <strong>Heads up.</strong>
            Applying a preset here replaces your {@row_count} existing rows with
            the preset's defaults. <strong>This cannot be undone.</strong>
            Existing row titles, card variants, and content wiring will be lost.
          </div>

          <div class="grid gap-4 md:grid-cols-3">
            <button
              :for={preset <- @presets}
              type="button"
              phx-click="preview_preset"
              phx-value-name={preset.name}
              data-test={"preset-card-" <> preset.name}
              class={[
                "text-left rounded-lg border p-4 transition",
                preset_card_class(preset.name, @selected_preset, @layout_config.preset_name)
              ]}
            >
              <div class="font-semibold">{preset.display_name}</div>
              <p class="text-sm opacity-70 mt-1">{preset.description}</p>
              <div class="mt-3 text-xs opacity-60">
                {length(preset.rows)} rows · {preset.display_font}
              </div>
            </button>
          </div>

          <div
            :if={@selected_preset != @layout_config.preset_name or @catalog_empty?}
            class="mt-4 flex flex-wrap gap-3 items-center"
          >
            <span class="text-sm opacity-70">
              Previewing <strong>{@selected_preset}</strong>.
            </span>

            <button
              :if={@catalog_empty?}
              type="button"
              phx-click="apply_preset"
              phx-value-name={@selected_preset}
              class="btn btn-primary btn-sm"
              data-test="apply-preset-btn"
            >
              Apply preset
            </button>

            <button
              :if={!@catalog_empty?}
              type="button"
              phx-click="confirm_overwrite_preset"
              phx-value-name={@selected_preset}
              data-confirm={"This will permanently delete your #{@row_count} existing rows and replace them with the #{@selected_preset} preset. Continue?"}
              class="btn btn-error btn-sm"
              data-test="overwrite-preset-btn"
            >
              Overwrite with preset
            </button>
          </div>
        </div>
      </details>

      <section class="mt-10" data-test="branding-editor">
        <h2 class="text-xl font-semibold mb-4">Brand</h2>
        <.form
          for={@branding_form}
          phx-change="preview_branding"
          phx-submit="save_branding"
          class="space-y-4 max-w-xl"
        >
          <div class="flex items-center gap-3">
            <.input
              field={@branding_form[:accent_color_base]}
              type="text"
              label="Accent color (oklch or hex)"
              placeholder="oklch(0.72 0.14 68)"
            />
            <div
              class="w-10 h-10 rounded-full border border-base-300"
              style={"background-color: " <> (@accent_preview || "transparent")}
              data-test="accent-swatch"
              aria-hidden="true"
            >
            </div>
          </div>

          <div style={display_font_style(@display_font_preview)}>
            <.input
              field={@branding_form[:display_font]}
              type="select"
              label="Display font"
              options={[{"System default", ""} | Enum.map(@display_fonts, &{&1, &1})]}
            />
            <p class="text-3xl mt-2" data-test="display-font-preview">
              The quick brown fox
            </p>
          </div>

          <button type="submit" class="btn btn-primary" data-test="save-branding-btn">
            Save branding
          </button>
        </.form>
      </section>

      <section class="mt-10" data-test="theme-editor">
        <h2 class="text-xl font-semibold mb-4">Surface colors</h2>

        <div class="sv-preview-container" data-test="theme-preview">
          <div class="sv-preview-editor">
            <.form for={@theme_form} phx-change="validate_theme" phx-submit="save_theme">
              <div class="space-y-4">
                <h3 class="text-lg font-medium">Colors</h3>
                <.color_input form={@theme_form} field={:background} label="Background" />
                <.color_input form={@theme_form} field={:surface} label="Surface" />
                <.color_input form={@theme_form} field={:elevated} label="Elevated" />
                <.color_input form={@theme_form} field={:text_primary} label="Text Primary" />
                <.color_input form={@theme_form} field={:text_secondary} label="Text Secondary" />
                <.color_input form={@theme_form} field={:text_on_accent} label="Text on Accent" />
                <.color_input form={@theme_form} field={:card_background} label="Card Background" />
                <.color_input form={@theme_form} field={:nav_background} label="Nav Background" />

                <h3 class="text-lg font-medium mt-6">Form Fields</h3>
                <.color_input form={@theme_form} field={:form_text} label="Input Text" />
                <.color_input form={@theme_form} field={:form_placeholder} label="Input Placeholder" />

                <h3 class="text-lg font-medium mt-6">Typography</h3>
                <.input field={@theme_form[:font_heading]} type="text" label="Heading Font" />
                <.input field={@theme_form[:font_body]} type="text" label="Body Font" />

                <h3 class="text-lg font-medium mt-6">Assets</h3>
                <.input field={@theme_form[:logo_url]} type="text" label="Logo URL" />
                <.input field={@theme_form[:favicon_url]} type="text" label="Favicon URL" />
                <.input
                  field={@theme_form[:login_background_image_url]}
                  type="text"
                  label="Login background image URL"
                  placeholder="https://example.com/login-bg.jpg"
                />

                <div class="mt-6">
                  <.button type="submit" data-test="theme-publish-btn">
                    Publish surface colors
                  </.button>
                </div>
              </div>
            </.form>
          </div>

          <div class="sv-preview-frame" data-test="theme-preview-frame">
            <div class="sv-root" style={Theme.build_css_vars(@preview_theme)}>
              <div style="padding: 12px 24px; background: var(--sv-nav-bg); display: flex; align-items: center; justify-content: space-between">
                <span style="font-family: var(--sv-font-heading); font-weight: 600; color: var(--sv-text-primary)">
                  {@organization.name}
                </span>
                <span style="font-size: 0.75rem; color: var(--sv-text-secondary)">
                  Home &nbsp; Browse &nbsp; Collections
                </span>
              </div>

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
            </div>
          </div>
        </div>
      </section>
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

  defp preset_card_class(name, selected, active) do
    cond do
      name == active -> "border-primary ring-2 ring-primary/30"
      name == selected -> "border-accent"
      true -> "border-base-300 hover:border-base-content/40"
    end
  end

  defp display_font_style(nil), do: ""
  defp display_font_style(""), do: ""

  defp display_font_style(font) when is_binary(font),
    do: "font-family: '#{font}', Georgia, serif;"
end
