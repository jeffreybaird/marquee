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

  alias Bobine.Accounts
  alias Bobine.Accounts.Organization
  alias Bobine.Branding
  alias Bobine.Branding.Theme
  alias Bobine.Catalog
  alias Bobine.Catalog.{Presets, Row}
  alias Bobine.Content.Video
  alias BobineWeb.Viewer.HomeLive.Components, as: ViewerHome

  @default_hero_seeds ~w(hero-cinema-1 hero-cinema-2 hero-cinema-3)
  @default_landscape_seeds ~w(land-1 land-2 land-3 land-4 land-5 land-6)
  @default_portrait_seeds ~w(port-1 port-2 port-3 port-4 port-5 port-6)
  @default_creator_seeds ~w(crea-1 crea-2 crea-3 crea-4 crea-5)

  @default_landscape_titles [
    "Echoes of the North",
    "Quiet Revolutions",
    "After Hours in Hanoi",
    "Field Notes",
    "The Dust Sessions",
    "Last Light"
  ]

  @default_portrait_titles [
    "La Jetée",
    "Le Mépris",
    "Cléo de 5 à 7",
    "Pierrot le Fou",
    "L'Atalante",
    "Hiroshima Mon Amour"
  ]

  @default_creator_titles [
    "Solveig Duret",
    "Marcus Thornton",
    "Keiko Abe",
    "Alma Sorin",
    "Theo Kamau"
  ]

  @default_hero_headlines [
    "A French cinema Sunday",
    "New release weekend",
    "Staff picks of the season"
  ]

  @default_hero_descriptions [
    "Tune the accent and text-on-accent pairing against the hero CTA viewers actually use.",
    "Verify the second slide's dot styling and arrow contrast match your accent.",
    "Confirm typography and gradient overlay readability on a real cinematic still."
  ]

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
     |> assign_preview_rows(org)
     |> assign_preview_hero_slides(org)
     |> assign(:preview_expanded, false)}
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
    scope = socket.assigns.current_scope
    theme = socket.assigns.theme

    org_params = params |> Map.get("organization", %{}) |> maybe_derive_accent_variants()
    theme_params = Map.get(params, "theme", %{})

    with {:branding, {:ok, updated_org}} <-
           {:branding, Accounts.update_organization_branding(org, org_params)},
         {:theme, {:ok, updated_theme}} <- {:theme, save_theme(scope, theme, theme_params, org)} do
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

  @impl true
  def handle_event("toggle_preview_expanded", _params, socket) do
    {:noreply, update(socket, :preview_expanded, &(!&1))}
  end

  # Cards rendered inside the preview emit viewer-side phx-clicks. Swallow
  # them so the appearance preview stays interactive without mutating data.
  @impl true
  def handle_event(event, _params, socket)
      when event in ~w(card_toggle_favorite card_add_to_watchlist card_add_to_queue dismiss_continue),
      do: {:noreply, socket}

  defp save_theme(_scope, %Theme{id: nil}, params, %{id: org_id}) do
    Branding.create_theme(Map.put(params, "organization_id", org_id))
  end

  defp save_theme(scope, %Theme{} = theme, params, _org),
    do: Branding.update_theme(scope, theme, params)

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
         |> assign_preview_hero_slides(org)
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
    row_count = Catalog.count_rows(org)

    socket
    |> assign(:row_count, row_count)
    |> assign(:catalog_empty?, row_count == 0)
  end

  # Load the operator's configured rows + items once on mount and after
  # preset apply/overwrite. Kept off `validate_appearance` on purpose —
  # branding edits fire on every keystroke and these rows don't change
  # during a form edit. When the org has no rows yet we synthesize a
  # default catalog so the preview reflects the real viewer surface.
  defp assign_preview_rows(socket, org) do
    rows_with_items =
      org
      |> Catalog.load_catalog_rows_with_items()
      |> Enum.reject(&preview_skip_row?/1)
      |> case do
        [] -> default_preview_rows()
        rows -> rows
      end

    assign(socket, :preview_rows, rows_with_items)
  end

  defp preview_skip_row?(%{row: %{source_type: type}})
       when type in [:welcome_text, :continue_watching],
       do: true

  defp preview_skip_row?(%{items: items}) when items == [], do: true
  defp preview_skip_row?(_), do: false

  defp assign_preview_hero_slides(socket, org) do
    enriched =
      case Catalog.get_hero_row(org) do
        {:ok, %Row{visible: true} = hero_row} ->
          Catalog.list_enriched_hero_slides(org, hero_row)

        _ ->
          []
      end

    slides = build_preview_hero_slides(enriched)

    assign(socket, :preview_hero_slides, slides)
  end

  defp build_preview_hero_slides(enriched) do
    enriched
    |> Enum.take(4)
    |> Enum.map(&normalize_preview_slide/1)
    |> pad_with_defaults()
  end

  defp normalize_preview_slide(slide) do
    %{
      headline:
        presence(Map.get(slide, :headline)) ||
          presence(Map.get(slide, :video_title)) ||
          List.first(@default_hero_headlines),
      subheadline: Map.get(slide, :subheadline),
      description:
        presence(Map.get(slide, :description)) ||
          presence(Map.get(slide, :video_description)) ||
          List.first(@default_hero_descriptions),
      brand_tag: presence(Map.get(slide, :brand_tag)) || "Featured",
      primary_cta_label: presence(Map.get(slide, :primary_cta_label)) || "Watch now",
      primary_cta_path: "#",
      secondary_cta_label: presence(Map.get(slide, :secondary_cta_label)) || "More info",
      secondary_cta_path: "#",
      background_image_url:
        presence(Map.get(slide, :background_image_url)) ||
          picsum_url(List.first(@default_hero_seeds), 1600, 900),
      title_logo_url: presence(Map.get(slide, :title_logo_url)),
      channel_logo_url: Map.get(slide, :channel_logo_url),
      show_headline: Map.get(slide, :show_headline, true),
      show_subheadline: Map.get(slide, :show_subheadline, false),
      show_description: Map.get(slide, :show_description, true),
      show_brand_tag: Map.get(slide, :show_brand_tag, true),
      show_primary_cta: Map.get(slide, :show_primary_cta, true),
      show_secondary_cta: Map.get(slide, :show_secondary_cta, true)
    }
  end

  defp pad_with_defaults(slides) when length(slides) >= 3, do: slides

  defp pad_with_defaults(slides) do
    needed = max(3 - length(slides), 0)

    extras =
      @default_hero_seeds
      |> Enum.zip(Enum.zip(@default_hero_headlines, @default_hero_descriptions))
      |> Enum.take(needed)
      |> Enum.map(fn {seed, {headline, description}} ->
        default_hero_slide(seed, headline, description)
      end)

    slides ++ extras
  end

  defp default_hero_slide(seed, headline, description) do
    %{
      headline: headline,
      subheadline: nil,
      description: description,
      brand_tag: "Featured",
      primary_cta_label: "Watch now",
      primary_cta_path: "#",
      secondary_cta_label: "More info",
      secondary_cta_path: "#",
      background_image_url: picsum_url(seed, 1600, 900),
      title_logo_url: nil,
      channel_logo_url: nil,
      show_headline: true,
      show_subheadline: false,
      show_description: true,
      show_brand_tag: true,
      show_primary_cta: true,
      show_secondary_cta: true
    }
  end

  defp default_preview_rows do
    [
      %{
        row: synthetic_row("hero-landscape", "Trending now", :recent, "landscape_episode"),
        items: synthetic_videos(@default_landscape_seeds, @default_landscape_titles, :landscape),
        view_all_path: nil
      },
      %{
        row: synthetic_row("posters", "Critics' picks", :popularity, "poster_portrait"),
        items: synthetic_videos(@default_portrait_seeds, @default_portrait_titles, :portrait),
        view_all_path: nil
      },
      %{
        row:
          synthetic_row("creators", "Featured creators", :creator_showcase, "creator_identity"),
        items: synthetic_videos(@default_creator_seeds, @default_creator_titles, :portrait, 1, 1),
        view_all_path: nil
      }
    ]
  end

  defp synthetic_row(slug, title, source_type, card_variant) do
    %Row{
      id: "preview-row-#{slug}",
      title: title,
      source_type: source_type,
      card_variant: card_variant,
      show_details: true,
      title_overlay: false,
      visible: true,
      position: 0,
      max_items: 8
    }
  end

  defp synthetic_videos(seeds, titles, aspect, ratio_w \\ nil, ratio_h \\ nil) do
    {w, h} = thumb_dimensions(aspect, ratio_w, ratio_h)

    seeds
    |> Enum.zip(titles)
    |> Enum.with_index()
    |> Enum.map(fn {{seed, title}, idx} -> synthetic_video(seed, title, aspect, w, h, idx) end)
  end

  defp thumb_dimensions(:portrait, nil, nil), do: {400, 600}
  defp thumb_dimensions(:landscape, nil, nil), do: {640, 360}
  defp thumb_dimensions(_, w, h), do: {w * 200, h * 200}

  defp synthetic_video(seed, title, aspect, w, h, idx) do
    url = picsum_url(seed, w, h)

    %Video{
      id: "preview-video-#{seed}",
      title: title,
      slug: "preview-#{seed}",
      description: "Sample synopsis for preview — viewer card description appears here.",
      duration: 1500.0 + idx * 90,
      mux_playback_id: nil,
      portrait_thumbnail_url: if(aspect == :portrait, do: url, else: nil),
      landscape_thumbnail_url: if(aspect == :landscape, do: url, else: nil)
    }
  end

  defp picsum_url(seed, w, h),
    do: "https://picsum.photos/seed/bobine-preview-#{seed}/#{w}/#{h}"

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
        class="mt-6 rounded-lg border border-admin-border"
        data-test="preset-drawer"
        open={@catalog_empty?}
      >
        <summary class="cursor-pointer px-4 py-3 text-sm font-medium">
          <span>Preset chooser</span>
          <span :if={!@catalog_empty?} class="ml-2 text-xs opacity-60">
            (advanced — overwrites your catalog)
          </span>
        </summary>

        <div class="border-t border-admin-border p-4" data-test="preset-picker">
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

            <BobineWeb.Components.AdminUI.admin_button
              :if={@catalog_empty?}
              type="button"
              phx-click="apply_preset"
              phx-value-name={@selected_preset}
              size={:sm}
              data-test="apply-preset-btn"
            >
              Apply preset
            </BobineWeb.Components.AdminUI.admin_button>

            <BobineWeb.Components.AdminUI.admin_button
              :if={!@catalog_empty?}
              type="button"
              phx-click="confirm_overwrite_preset"
              phx-value-name={@selected_preset}
              data-confirm={"This will permanently delete your #{@row_count} existing rows and replace them with the #{@selected_preset} preset. Continue?"}
              variant={:danger}
              size={:sm}
              data-test="overwrite-preset-btn"
            >
              Overwrite with preset
            </BobineWeb.Components.AdminUI.admin_button>
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
                <.color_input
                  form={@branding_form}
                  field={:accent_color_base}
                  label="Accent color"
                  hint="Primary brand accent. Buttons, links, focus rings, hero CTAs, and progress bars pull from this color."
                />

                <details class="rounded border border-admin-border" data-test="accent-variants-drawer">
                  <summary class="cursor-pointer px-3 py-2 text-sm">
                    Accent variants
                    <span class="ml-1 text-xs opacity-60">
                      (auto-derived — leave blank to compute from accent color)
                    </span>
                  </summary>
                  <div class="space-y-4 px-3 pb-3 pt-2">
                    <.color_input
                      form={@branding_form}
                      field={:accent_color_hover}
                      label="Accent (hover)"
                      hint="Used on accent buttons and links on hover. Defaults to accent shifted +6% lightness."
                    />
                    <.color_input
                      form={@branding_form}
                      field={:accent_color_active}
                      label="Accent (active)"
                      hint="Used on accent buttons while pressed. Defaults to accent shifted -6% lightness."
                    />
                    <.color_input
                      form={@branding_form}
                      field={:accent_color_subtle}
                      label="Accent (subtle)"
                      hint="Tinted accent backgrounds — selection highlights, badge fills. Defaults to a darkened/desaturated accent."
                    />
                  </div>
                </details>

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
                <.color_input
                  form={@theme_form}
                  field={:border_color}
                  label="Border"
                  hint="Hairline borders on cards, scrollbars, and content row dividers."
                />
                <.color_input
                  form={@theme_form}
                  field={:divider_color}
                  label="Divider"
                  hint="Section dividers and inline rules between content blocks."
                />
                <.color_input
                  form={@theme_form}
                  field={:overlay_color}
                  label="Overlay"
                  hint="Backdrop fill for modals, dialogs, and pop-ups. Usually a translucent dark or light wash."
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
            hero_slides={@preview_hero_slides}
            expanded={@preview_expanded}
          />
          <p class="mt-3 text-xs opacity-60">
            Reflects brand + surface color changes live.
          </p>
        </div>
      </div>

      <%!-- Full-screen canonical preview — renders through the same shared
           viewer_home_body component as the real viewer home, so the two
           cannot drift. --%>
      <div
        :if={@preview_expanded}
        class="fixed inset-0 z-50 overflow-y-auto"
        role="dialog"
        aria-modal="true"
        aria-label="Full-size appearance preview"
        data-test="preview-expanded-overlay"
      >
        <div
          class="sv-root min-h-full"
          style={
            preview_style(%{
              preview_theme: @preview_theme,
              accent_preview: @accent_preview,
              display_font_preview: @display_font_preview
            })
          }
        >
          <ViewerHome.viewer_home_body
            hero_slides={@preview_hero_slides}
            rows={@preview_rows}
            hero_id="appearance-preview-hero"
            catalog_rows_test="preview-expanded-catalog-rows"
          />
        </div>
        <button
          type="button"
          phx-click="toggle_preview_expanded"
          class="fixed top-4 right-4 z-10 rounded-full bg-black/60 p-2 text-white hover:bg-black/80 focus:outline-none focus-visible:ring-2 focus-visible:ring-white"
          aria-label="Close full-size preview"
          data-test="close-preview-expanded"
        >
          <.icon name="hero-x-mark" class="size-5" aria-hidden="true" />
        </button>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  attr :organization, :map, required: true
  attr :preview_theme, :map, required: true
  attr :accent_preview, :string, default: nil
  attr :display_font_preview, :string, default: nil
  attr :rows, :list, default: []
  attr :hero_slides, :list, default: []
  attr :expanded, :boolean, default: false

  defp preview_panel(assigns) do
    assigns = assign(assigns, :style, preview_style(assigns))

    ~H"""
    <div class="relative">
      <button
        type="button"
        phx-click="toggle_preview_expanded"
        class="absolute top-2 right-2 z-10 rounded-md bg-black/60 p-1.5 text-white hover:bg-black/80 focus:outline-none focus-visible:ring-2 focus-visible:ring-white"
        aria-label={
          if @expanded, do: "Close full-size preview", else: "Expand preview to full screen"
        }
        data-test="expand-preview-btn"
      >
        <.icon
          name={if @expanded, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
          class="size-4"
          aria-hidden="true"
        />
      </button>
      <div
        class="sv-preview-frame rounded-lg border border-admin-border overflow-hidden"
        data-test="preview-frame"
      >
        <div
          class="sv-root sv-preview-frame-inner"
          style={"max-height: 720px; overflow-y: auto; " <> @style}
        >
          <div
            class="sv-preview-faux-nav"
            style="padding: 12px 24px; background: var(--sv-nav-bg); display: flex; align-items: center; justify-content: space-between"
          >
            <span style="font-family: var(--sv-font-heading); font-weight: 600; color: var(--sv-text-primary)">
              {@organization.name}
            </span>
            <span style="font-size: 0.75rem; font-family: var(--sv-font-body); color: var(--sv-text-secondary)">
              Home &nbsp; Browse &nbsp; Collections
            </span>
          </div>

          <ViewerHome.hero_carousel
            :if={!@expanded}
            id="appearance-inline-preview-hero"
            slides={@hero_slides}
            auto_advance_ms={0}
          />

          <section
            :if={!@expanded}
            class="catalog-rows"
            data-test="preview-catalog-rows"
          >
            <ViewerHome.content_row
              :for={%{row: row, items: items} <- @rows}
              row={row}
              items={items}
            />
          </section>
        </div>
      </div>
    </div>
    """
  end

  defp presence(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp presence(value), do: value

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
    field = assigns.form[assigns.field]
    raw_value = field.value

    errors =
      if Phoenix.Component.used_input?(field),
        do: Enum.map(field.errors, &BobineWeb.CoreComponents.translate_error/1),
        else: []

    assigns =
      assigns
      |> assign(:input_name, field.name)
      |> assign(:text_value, raw_value)
      |> assign(:picker_value, to_hex_picker_value(raw_value))
      |> assign(:errors, errors)

    ~H"""
    <div
      class="flex items-center gap-3"
      title={@hint}
      data-test={"color-input-" <> Atom.to_string(@field)}
    >
      <label
        class="flex items-center gap-1 text-sm font-medium text-admin-fg min-w-[140px]"
        title={@hint}
      >
        {@label}
        <span
          :if={@hint}
          class="inline-flex items-center justify-center w-4 h-4 rounded-full border border-admin-border text-[10px] font-semibold opacity-70 cursor-help"
          title={@hint}
          aria-label={@hint}
        >
          ?
        </span>
      </label>
      <span
        class="relative inline-flex h-8 w-8 cursor-pointer rounded border border-admin-border bg-[conic-gradient(at_50%_50%,_#fff,_#bbb,_#fff,_#bbb,_#fff)]"
        title={@hint}
      >
        <span
          class="absolute inset-0 rounded"
          style={"background: " <> swatch_color(@text_value)}
          data-test={"color-swatch-" <> Atom.to_string(@field)}
          aria-hidden="true"
        />
        <input
          type="color"
          value={@picker_value}
          class="absolute inset-0 cursor-pointer opacity-0"
          title={@hint}
          aria-label={"Pick #{@label} (hex only)"}
          oninput="var t=this.closest('[data-test^=color-input]').querySelector('input[type=text]'); t.value=this.value; t.dispatchEvent(new Event('input',{bubbles:true})); var s=this.previousElementSibling; if(s) s.style.background=this.value;"
        />
      </span>
      <input
        type="text"
        name={@input_name}
        value={@text_value}
        class="rounded-md border border-admin-border bg-admin-card px-2 py-1 text-sm text-admin-fg focus:border-admin-accent focus:outline-none w-44"
        placeholder="#000000 or oklch(...)"
        title={@hint}
        oninput="var w=this.closest('[data-test^=color-input]').querySelector('[data-test^=color-swatch]'); if(w) w.style.background=this.value || 'transparent'; var p=this.closest('[data-test^=color-input]').querySelector('input[type=color]'); if(/^#[0-9a-fA-F]{6}$/.test(this.value)) p.value=this.value;"
      />
      <p :for={msg <- @errors} class="text-sm text-red-500">{msg}</p>
    </div>
    """
  end

  # Pass the raw value straight through as a CSS background. Both `#rrggbb`
  # and `oklch(...)` are valid background values, so the swatch shows the
  # operator's actual color regardless of format. Empty values fall back to
  # transparent so the checkered pattern shows the cell is unset.
  defp swatch_color(v) when is_binary(v) and v != "", do: v
  defp swatch_color(_), do: "transparent"

  defp to_hex_picker_value(v) when is_binary(v) do
    case Regex.run(~r/^#[0-9a-fA-F]{6}$/, v) do
      [match] -> String.downcase(match)
      _ -> "#000000"
    end
  end

  defp to_hex_picker_value(_), do: "#000000"

  defp preset_card_class(name, selected, active) do
    cond do
      name == active -> "border-primary ring-2 ring-primary/30"
      name == selected -> "border-accent"
      true -> "border-admin-border hover:border-admin-border"
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
      |> Enum.map_join("&", fn name ->
        encoded = String.replace(name, " ", "+")
        "family=#{encoded}:wght@400;500;600"
      end)

    "https://fonts.googleapis.com/css2?#{families}&display=swap"
  end
end
