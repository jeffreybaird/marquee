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
     |> assign(:body_fonts, Organization.approved_body_fonts())
     |> assign(:theme, theme)
     |> assign(:preview_theme, theme)
     |> assign(:theme_form, theme_form)
     |> assign_catalog_state(org)
     |> assign_preview_rows(org)}
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
  def handle_event("validate_appearance", params, socket) do
    org_params = Map.get(params, "organization", %{})
    theme_params = Map.get(params, "theme", %{})

    theme = socket.assigns.theme
    preview = apply_theme_preview(theme, theme_params)

    {:noreply,
     socket
     |> assign(:accent_preview, Map.get(org_params, "accent_color_base") || "")
     |> assign(:display_font_preview, Map.get(org_params, "display_font") || "")
     |> assign(
       :branding_form,
       socket.assigns.organization
       |> Organization.branding_changeset(org_params)
       |> to_form()
     )
     |> assign(:theme_form, theme |> Branding.change_theme(theme_params) |> to_form())
     |> assign(:preview_theme, preview)}
  end

  @impl true
  def handle_event("save_appearance", params, socket) do
    org = socket.assigns.organization
    theme = socket.assigns.theme

    org_params = params |> Map.get("organization", %{}) |> maybe_derive_accent_variants()
    theme_params = Map.get(params, "theme", %{})

    with {:branding, {:ok, updated_org}} <-
           {:branding, Accounts.update_organization_branding(org, org_params)},
         {:theme, {:ok, updated_theme}} <- {:theme, save_theme(theme, theme_params, org)} do
      {:noreply,
       socket
       |> assign(:organization, updated_org)
       |> assign(:theme, updated_theme)
       |> assign(:preview_theme, updated_theme)
       |> assign(:theme_form, to_form(Branding.change_theme(updated_theme)))
       |> assign(
         :branding_form,
         updated_org |> Organization.branding_changeset(%{}) |> to_form()
       )
       |> put_flash(:info, "Appearance saved.")}
    else
      {:branding, {:error, :validation, cs}} ->
        {:noreply, assign(socket, :branding_form, to_form(cs))}

      {:theme, {:error, :validation, cs}} ->
        {:noreply, assign(socket, :theme_form, to_form(cs))}
    end
  end

  defp save_theme(%Theme{id: nil}, params, %{id: org_id}) do
    Branding.create_theme(Map.put(params, "organization_id", org_id))
  end

  defp save_theme(%Theme{} = theme, params, _org), do: Branding.update_theme(theme, params)

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
        org = socket.assigns.organization

        {:noreply,
         socket
         |> assign(:layout_config, layout)
         |> assign(:selected_preset, layout.preset_name)
         |> assign_catalog_state(org)
         |> assign_preview_rows(org)
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

  # Load the operator's configured rows once on mount and after preset
  # apply/overwrite. Kept off `validate_appearance` on purpose — branding
  # edits fire on every keystroke and these rows don't change during a
  # form edit.
  defp assign_preview_rows(socket, org) do
    rows =
      Row
      |> where(organization_id: ^org.id)
      |> where([r], is_nil(r.deleted_at))
      |> where([r], r.visible == true)
      |> order_by(asc: :position)
      |> limit(6)
      |> Repo.all()

    assign(socket, :preview_rows, rows)
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
      <link rel="dns-prefetch" href="https://fonts.googleapis.com" />
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
      <link rel="stylesheet" href={admin_fonts_href(@display_fonts, @body_fonts)} />

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

      <div
        class="mt-10 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]"
        data-test="branding-editor"
      >
        <div class="space-y-10">
          <.form
            for={@branding_form}
            phx-change="validate_appearance"
            phx-submit="save_appearance"
            class="space-y-10"
          >
            <section>
              <h2 class="text-xl font-semibold mb-4">Brand</h2>
              <div class="space-y-4">
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
                    title="Primary brand accent. Buttons, links, focus rings, and progress bars pull from this color."
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

                <h3 class="text-lg font-medium mt-6">Typography</h3>
                <.input
                  field={@theme_form[:font_heading]}
                  type="select"
                  label="Heading font"
                  options={[{"System default", ""} | Enum.map(@display_fonts, &{&1, &1})]}
                />
                <.input
                  field={@theme_form[:font_body]}
                  type="select"
                  label="Body font"
                  options={[{"System default", ""} | Enum.map(@body_fonts, &{&1, &1})]}
                />

                <h3 class="text-lg font-medium mt-6">Assets</h3>
                <.input field={@theme_form[:logo_url]} type="text" label="Logo URL" />
                <.input field={@theme_form[:favicon_url]} type="text" label="Favicon URL" />
                <.input
                  field={@theme_form[:login_background_image_url]}
                  type="text"
                  label="Login background image URL"
                  placeholder="https://example.com/login-bg.jpg"
                />
              </div>
            </section>

            <section data-test="theme-editor">
              <h2 class="text-xl font-semibold mb-4">Surface colors</h2>
              <p class="text-sm opacity-70 mb-4">
                Hover any field for a hint on where it shows up. Changes stream
                to the preview as you edit.
              </p>

              <div class="space-y-4">
                <h3 class="text-lg font-medium">Colors</h3>
                <.color_input
                  form={@theme_form}
                  field={:background}
                  label="Background"
                  hint="Page background behind every viewer surface. Set the darkest or lightest canvas first — other surfaces layer on top."
                />
                <.color_input
                  form={@theme_form}
                  field={:surface}
                  label="Surface"
                  hint="Cards, panels, and content row backgrounds. Usually one shade lighter than Background."
                />
                <.color_input
                  form={@theme_form}
                  field={:elevated}
                  label="Elevated"
                  hint="Raised elements — dropdowns, dialogs, inline menus. Usually another step lighter than Surface."
                />
                <.color_input
                  form={@theme_form}
                  field={:text_primary}
                  label="Text Primary"
                  hint="Main body and heading text. Needs at least 4.5:1 contrast with Background."
                />
                <.color_input
                  form={@theme_form}
                  field={:text_secondary}
                  label="Text Secondary"
                  hint="Subtitles, metadata, descriptions. Softer than primary text."
                />
                <.color_input
                  form={@theme_form}
                  field={:text_on_accent}
                  label="Text on Accent"
                  hint="Foreground color for text placed on top of the accent color (buttons, badges). Needs contrast with your accent."
                />
                <.color_input
                  form={@theme_form}
                  field={:card_background}
                  label="Card Background"
                  hint="Individual content card fill on the catalog. Usually matches Surface or sits just above it."
                />
                <.color_input
                  form={@theme_form}
                  field={:nav_background}
                  label="Nav Background"
                  hint="Top navigation bar fill. Often semi-transparent over the page background."
                />

                <h3 class="text-lg font-medium mt-6">Form Fields</h3>
                <.color_input
                  form={@theme_form}
                  field={:form_text}
                  label="Input Text"
                  hint="Color of text typed into login, search, and form inputs."
                />
                <.color_input
                  form={@theme_form}
                  field={:form_placeholder}
                  label="Input Placeholder"
                  hint="Dimmer placeholder text inside empty inputs before the viewer types."
                />
              </div>
            </section>

            <div class="pt-4">
              <.button type="submit" data-test="save-branding-btn">
                Save appearance
              </.button>
            </div>
          </.form>
        </div>

        <div class="lg:sticky lg:top-4 self-start">
          <h2 class="text-xl font-semibold mb-4">Preview</h2>
          <.preview_panel
            organization={@organization}
            preview_theme={@preview_theme}
            accent_preview={@accent_preview}
            display_font_preview={@display_font_preview}
            rows={@preview_rows}
          />
          <p class="mt-3 text-xs opacity-60">
            Reflects brand + surface color changes live.
          </p>
        </div>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  attr :organization, :map, required: true
  attr :preview_theme, :map, required: true
  attr :accent_preview, :string, default: nil
  attr :display_font_preview, :string, default: nil
  attr :rows, :list, default: []

  defp preview_panel(assigns) do
    {hero, content_rows} = split_hero(assigns.rows)

    assigns =
      assigns
      |> assign(:style, preview_style(assigns))
      |> assign(:hero_row, hero)
      |> assign(:content_rows, content_rows)

    ~H"""
    <div
      class="sv-preview-frame rounded-lg overflow-hidden border border-base-300"
      data-test="preview-frame"
    >
      <div class="sv-root" style={@style}>
        <div style="padding: 12px 24px; background: var(--sv-nav-bg); display: flex; align-items: center; justify-content: space-between">
          <span style="font-family: var(--sv-font-heading); font-weight: 600; color: var(--sv-text-primary)">
            {@organization.name}
          </span>
          <span style="font-size: 0.75rem; font-family: var(--sv-font-body); color: var(--sv-text-secondary)">
            Home &nbsp; Browse &nbsp; Collections
          </span>
        </div>

        <.preview_hero row={@hero_row} />

        <div
          :if={@content_rows == []}
          style="padding: 24px; text-align: center; color: var(--sv-text-secondary); font-family: var(--sv-font-body); font-size: 0.875rem"
        >
          No rows configured yet. Apply a preset above or add rows in Catalog.
        </div>

        <div
          :for={row <- @content_rows}
          style="padding: 12px 24px"
          data-test={"preview-row-" <> row.id}
        >
          <div style="font-family: var(--sv-font-heading); font-size: 0.9rem; font-weight: 600; color: var(--sv-text-primary); margin-bottom: 8px">
            {row.title}
          </div>
          <div style="display: flex; gap: 8px; overflow: hidden">
            <div
              :for={_i <- 1..preview_card_count(row)}
              style={"flex-shrink: 0; width: #{preview_card_width(row)}px; background: var(--sv-card-bg); border-radius: 4px; overflow: hidden"}
            >
              <div style={"aspect-ratio: #{preview_aspect(row)}; background: var(--sv-bg-elevated)"} />
              <div style="padding: 6px">
                <div style="height: 8px; width: 80%; background: var(--sv-bg-elevated); border-radius: 2px" />
              </div>
            </div>
          </div>
        </div>

        <p style="padding: 0 24px 16px; font-family: var(--sv-font-body); font-size: 0.75rem; line-height: 1.5; color: var(--sv-text-secondary)">
          Body font sample — synopses, curator notes, and descriptions pick up this typeface.
        </p>
      </div>
    </div>
    """
  end

  attr :row, :map, default: nil

  defp preview_hero(assigns) do
    ~H"""
    <div style="min-height: 200px; background: linear-gradient(135deg, var(--sv-bg-secondary), var(--sv-bg-primary)); display: flex; align-items: flex-end; padding: 24px">
      <div>
        <div style="font-size: 0.625rem; text-transform: uppercase; letter-spacing: 0.1em; color: var(--sv-text-secondary); margin-bottom: 4px; font-family: var(--sv-font-body)">
          {hero_label(@row)}
        </div>
        <div style="font-family: var(--font-display, var(--sv-font-heading)); font-size: 1.75rem; font-weight: 500; color: var(--sv-text-primary); letter-spacing: -0.01em; line-height: 1.1">
          {hero_title(@row)}
        </div>
        <p style="font-family: var(--sv-font-body); font-size: 0.8125rem; line-height: 1.5; color: var(--sv-text-secondary); margin-top: 8px; max-width: 360px">
          Your display font lives up here, your body font lives in this paragraph, and your accent is the button below.
        </p>
        <div style="margin-top: 10px">
          <span style="display: inline-block; padding: 6px 16px; background: var(--sv-accent); color: var(--sv-text-on-accent); border-radius: 4px; font-size: 0.75rem; font-weight: 500; font-family: var(--sv-font-heading)">
            Watch now
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp split_hero(rows) do
    case Enum.split_with(rows, &(&1.source_type == :hero)) do
      {[hero | _], content} -> {hero, content}
      {[], content} -> {nil, content}
    end
  end

  defp hero_label(nil), do: "Featured"
  defp hero_label(%Row{title: title}) when is_binary(title) and title != "", do: title
  defp hero_label(_), do: "Featured"

  defp hero_title(nil), do: "A French cinema Sunday"
  defp hero_title(_), do: "A French cinema Sunday"

  # Map a row's card_variant to an aspect ratio + card width that matches
  # the real viewer layout, so operators see the shape of their catalog.
  defp preview_aspect(%Row{card_variant: variant}) do
    case variant do
      "poster_portrait" -> "2 / 3"
      "creator_identity" -> "1 / 1"
      "collection_editorial" -> "3 / 2"
      "minimal_list_item" -> "2 / 3"
      _ -> "16 / 9"
    end
  end

  defp preview_card_width(%Row{card_variant: "poster_portrait"}), do: 64
  defp preview_card_width(%Row{card_variant: "minimal_list_item"}), do: 64
  defp preview_card_width(%Row{card_variant: "creator_identity"}), do: 72
  defp preview_card_width(_), do: 100

  defp preview_card_count(%Row{card_variant: "creator_identity"}), do: 5
  defp preview_card_count(%Row{card_variant: "poster_portrait"}), do: 5
  defp preview_card_count(_), do: 4

  # Merge Theme-driven `--sv-*` vars with Organization-driven tokens so the
  # preview reflects both the Brand form (accent + display font) and the
  # Surface colors form (everything else) in real time.
  defp preview_style(assigns) do
    theme_css = Theme.build_css_vars(assigns.preview_theme)

    accent =
      case assigns.accent_preview do
        a when is_binary(a) and a != "" -> "--color-accent: #{a}; --color-accent-hover: #{a};"
        _ -> ""
      end

    font =
      case assigns.display_font_preview do
        f when is_binary(f) and f != "" ->
          "--font-display: '#{f}', Georgia, serif;"

        _ ->
          ""
      end

    [theme_css, accent, font]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  attr :form, :map, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :hint, :string, default: nil

  defp color_input(assigns) do
    ~H"""
    <div
      class="flex items-center gap-3"
      title={@hint}
      data-test={"color-input-" <> Atom.to_string(@field)}
    >
      <label
        class="flex items-center gap-1 text-sm font-medium text-base-content min-w-[140px]"
        title={@hint}
      >
        {@label}
        <span
          :if={@hint}
          class="inline-flex items-center justify-center w-4 h-4 rounded-full border border-base-content/30 text-[10px] font-semibold opacity-70 cursor-help"
          title={@hint}
          aria-label={@hint}
        >
          ?
        </span>
      </label>
      <input
        type="color"
        name={"theme[#{@field}]"}
        value={Phoenix.HTML.Form.input_value(@form, @field) || "#000000"}
        class="h-8 w-8 cursor-pointer rounded border border-base-300"
        title={@hint}
      />
      <input
        type="text"
        name={"theme[#{@field}]"}
        value={Phoenix.HTML.Form.input_value(@form, @field)}
        class="input input-bordered input-sm w-36"
        placeholder="#000000"
        title={@hint}
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

  # Build a single Google Fonts URL preloading every approved display and
  # body font so the live preview can render whichever the operator selects
  # without a per-font round trip on every `phx-change`.
  defp admin_fonts_href(display_fonts, body_fonts) do
    families =
      (display_fonts ++ body_fonts)
      |> Enum.uniq()
      |> Enum.map(fn name ->
        encoded = name |> String.replace(" ", "+")
        "family=#{encoded}:wght@400;500;600"
      end)
      |> Enum.join("&")

    "https://fonts.googleapis.com/css2?#{families}&display=swap"
  end
end
