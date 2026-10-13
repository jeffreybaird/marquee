defmodule MarqueeFeatures.Steps.Branding do
  @moduledoc """
  Step definitions for branding.feature.

  Covers preset selection + apply flows on the appearance page (including
  the catalog layout-preset overwrite/cancel flows), accent colour and font
  overrides, theme propagation, the full-screen and mini previews, and the
  organization branding settings (admin accent colour, custom domain).

  Computed colours are compared through a probe element: the step paints a
  throwaway element with the expected value and with the CSS variable under
  test, so `#hex`, `rgb()` and `oklch()` spellings normalise identically.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Browser, except: [refute_has: 2]
  import Wallaby.Query
  import ExUnit.Assertions
  import Marquee.Factory
  import MarqueeFeatures.Support.Browser

  alias Marquee.Accounts
  alias Marquee.Branding
  alias Marquee.Catalog
  alias Marquee.Catalog.Presets
  alias Marquee.Events
  alias Marquee.Repo

  # The appearance page offers the catalog layout presets from
  # `Marquee.Catalog.Presets` (catalog_cinema / learning_platform /
  # creator_channel). A fresh organization already has `catalog_cinema`
  # recorded on its layout, so preview a different one — otherwise "not
  # persisted until I apply" could never fail.
  @preview_preset_name "learning_platform"

  # A colour no preset ships, so its presence proves the unsaved draft is
  # what the viewer site rendered.
  @unsaved_background "#123456"
  @background_input "[data-test=color-input-background] input[type=text]"

  @custom_accent_base "#1d4ed8"
  @custom_accent_hover "oklch(0.62 0.19 262)"
  @custom_accent_active "#1e3a8a"
  @custom_admin_accent "#0f766e"
  @display_font "Playfair Display"
  @body_font "Merriweather"
  @propagated_background "#224466"
  @cta_style_props ~w(backgroundColor color borderRadius fontWeight fontSize paddingTop paddingLeft)

  when_("I select a layout preset such as Learning Platform", fn world ->
    session = select_preset(world.session, @preview_preset_name)
    Map.merge(world, %{session: session, preview_preset: @preview_preset_name})
  end)

  then_("the preset is shown as previewing", fn world ->
    assert_has(
      world.session,
      css("[data-test=preset-picker]", text: "Previewing #{world.preview_preset}")
    )

    world
  end)

  then_("when I apply it the catalog layout uses that preset", fn world ->
    session = apply_selected_preset(world.session, world.org)
    assert persisted_preset(world.org) == world.preview_preset
    Map.put(world, :session, session)
  end)

  given_("I have previewed a layout preset", fn world ->
    session =
      world.session
      |> visit_live("/admin/appearance?org=#{world.org.slug}")
      |> select_preset(@preview_preset_name)

    Map.merge(world, %{session: session, preview_preset: @preview_preset_name})
  end)

  when_("I confirm and apply the preset", fn world ->
    Map.put(world, :session, apply_selected_preset(world.session, world.org))
  end)

  then_("the preset is saved on the catalog layout", fn world ->
    assert persisted_preset(world.org) == world.preview_preset
    world
  end)

  then_("the catalog rows are seeded from that preset", fn world ->
    {:ok, preset} = Presets.get(world.preview_preset)
    %{results: rows} = Catalog.list_rows(world.org)

    # A preset row's row_type becomes the catalog row's source_type.
    actual = rows |> Enum.map(&{to_string(&1.source_type), to_string(&1.card_variant)}) |> Enum.sort()
    expected = preset.rows |> Enum.map(&{to_string(&1.row_type), to_string(&1.card_variant)}) |> Enum.sort()

    assert actual == expected,
           "expected the catalog rows to be seeded from the #{world.preview_preset} preset"

    world
  end)

  # ---- Preview without applying -------------------------------------------

  when_("I hover over or click preview on a preset", fn world ->
    session = select_preset(world.session, @preview_preset_name)
    Map.merge(world, %{session: session, preview_preset: @preview_preset_name})
  end)

  then_("the catalog layout is not changed until I apply", fn world ->
    refute persisted_preset(world.org) == world.preview_preset,
           "expected #{world.preview_preset} NOT to be persisted before apply"

    %{results: rows} = Catalog.list_rows(world.org)
    assert rows == [], "expected no catalog rows to be seeded before apply"

    world
  end)

  # ---- Preset helpers -----------------------------------------------------

  # The preset drawer is a <details> that is open when the catalog is empty
  # and collapsed otherwise; clicking its summary toggles it, so only click
  # when it is still closed.
  defp open_preset_drawer(session) do
    if has?(session, css("[data-test=preset-drawer][open]")) do
      session
    else
      click(session, css("[data-test=preset-drawer] summary"))
    end
  end

  defp select_preset(session, name) do
    session
    |> await_live_connect()
    |> open_preset_drawer()
    |> click(css("[data-test=preset-card-#{name}]"))
    # With rows in the catalog the drawer renders closed (open={@catalog_empty?}),
    # and the patch that stages the preview collapses it again; the operator
    # reopens it to see the preview and its apply/overwrite controls.
    |> await_preset_preview(name, 20)
  end

  defp await_preset_preview(session, name, 0) do
    assert_has(session, css("[data-test=preset-picker]", text: "Previewing #{name}"))
  end

  defp await_preset_preview(session, name, attempts) do
    preview = css("[data-test=preset-picker]", text: "Previewing #{name}")

    if has?(session, preview) do
      session
    else
      session
      |> open_preset_drawer()
      |> await_preset_preview(name, attempts - 1)
    end
  end

  # An empty catalog applies directly; a populated one asks for confirmation
  # before overwriting. Once applied the selected preset equals the saved
  # one, so the "Previewing" block (and its button) disappears — wait for
  # that before reading the database.
  defp apply_selected_preset(session, org) do
    %{results: rows} = Catalog.list_rows(org)

    if rows == [] do
      session
      |> click(css("[data-test=apply-preset-btn]"))
      |> refute_has(css("[data-test=apply-preset-btn]"))
    else
      accept_confirm(session, fn s -> click(s, css("[data-test=overwrite-preset-btn]")) end)
      refute_has(session, css("[data-test=overwrite-preset-btn]"))
    end
  end

  defp persisted_preset(org) do
    {:ok, layout} = Catalog.get_or_create_layout(org)
    layout.preset_name
  end

  # ---- Mini preview reuses canonical viewer components ---------------------

  then_("the mini preview renders the canonical hero carousel component", fn world ->
    assert_has(world.session, css("[data-test=preview-frame] [data-test=hero-carousel]"))
    world
  end)

  then_("the mini preview renders the canonical content row component", fn world ->
    # Every preview row renders through the canonical component; the sample
    # catalog ships several rows, so ask for "at least one" rather than one.
    assert_has(world.session, css("[data-test=preview-catalog-rows] .content-row", minimum: 1))
    world
  end)

  then_(
    "default hero, landscape, and portrait images populate the preview when the catalog is empty",
    fn world ->
      %{results: rows} = Catalog.list_rows(world.org)
      assert rows == [], "expected an empty catalog for default-image preview check"
      assert_has(world.session, css("[data-test=hero-slide-0] img[src*='picsum.photos']"))
      assert_has(world.session, css("[data-test=preview-catalog-rows] img[src*='picsum.photos']", minimum: 1))
      world
    end
  )

  # ---- Unsaved draft survives navigating into the viewer site (issue #21) --

  given_("my catalog has a published video", fn world ->
    video =
      insert(:video,
        organization: world.org,
        title: "Draft Preview Video",
        mux_status: "ready",
        published: true
      )

    # A visible curated row holding the video makes the appearance preview
    # render a real `/watch/<id>` card link, exactly like the viewer home.
    row =
      insert(:row,
        organization: world.org,
        title: "Draft Preview Row",
        source_type: :curated,
        visible: true,
        position: 0
      )

    insert(:row_item, organization: world.org, row: row, video: video, position: 0)

    Map.put(world, :video, video)
  end)

  when_("I change the background color without saving", fn world ->
    session =
      world.session
      |> fill_in(css(@background_input), with: @unsaved_background)

    # `phx-change` streams the draft into the inline preview; wait for it so
    # the navigation that follows happens after the draft has been stored.
    assert_has(
      session,
      css("[data-test=preview-frame] [style*='--sv-bg-primary: #{@unsaved_background}']")
    )

    Map.merge(world, %{session: session, unsaved_background: @unsaved_background})
  end)

  when_("I click a video inside the preview", fn world ->
    session =
      world.session
      |> click(css("[data-test=preview-frame] .sv-card-thumb-link", at: 0))

    # The card is a real viewer link, so this is a full page load into the
    # viewer site's watch page. Landing anywhere else (for example `/login`)
    # means the preview session did not carry over into the viewer site.
    assert_has(session, css("[data-test=sv-root]"))
    landed_on = current_path(session)

    assert landed_on =~ "/watch/#{world.video.id}",
           "expected the preview card to open the viewer watch page, landed on #{landed_on}"

    Map.put(world, :session, session)
  end)

  then_("the viewer page shows my unsaved background color", fn world ->
    root = find(world.session, css("[data-test=sv-root]"))

    assert Element.attr(root, "style") =~ "--sv-bg-primary: #{world.unsaved_background}",
           "expected the viewer site to render the unsaved background colour"

    world
  end)

  then_("a banner offers to take me back to the editor", fn world ->
    assert_has(world.session, css("[data-test=impersonation-banner]"))
    assert_has(world.session, css("[data-test=appearance-preview-notice]"))
    assert_has(world.session, css("[data-test=appearance-preview-editor-link]"))
    world
  end)

  when_("I return to the editor from the banner", fn world ->
    session =
      world.session
      |> click(css("[data-test=appearance-preview-editor-link]"))

    assert_has(session, css("[data-test=appearance-preview-restored]"))
    assert String.contains?(current_path(session), "/admin/appearance")

    Map.put(world, :session, session)
  end)

  then_("the background color input still holds my unsaved value", fn world ->
    input = find(world.session, css(@background_input))

    assert Element.value(input) == world.unsaved_background,
           "expected the editor to restore the unsaved background colour"

    world
  end)

  when_("I open Appearance from the admin sidebar", fn world ->
    session =
      world.session
      |> resize_window(1440, 1000)
      |> visit("/admin?org=#{world.org.slug}")
      |> click(css("[data-test=admin-nav-appearance]"))
      |> assert_has(css("[data-test=preview-frame]"))

    Map.put(world, :session, session)
  end)

  when_("I leave Appearance through the dashboard sidebar", fn world ->
    session =
      world.session
      |> resize_window(1440, 1000)
      |> click(css("[data-test=admin-nav-dashboard]"))
      |> assert_has(css("h1", text: "Dashboard"))

    Map.put(world, :session, session)
  end)

  then_("the public browse page shows no draft or member preview", fn world ->
    session =
      world.session
      |> visit("/browse")
      |> refute_has(css("[data-test=appearance-preview-notice]"))
      |> refute_has(css("[data-test=impersonation-banner]"))
      |> refute_has(css("[data-test=sv-root][style*='--sv-bg-primary: #{@unsaved_background}']"))

    Map.put(world, :session, session)
  end)

  # ---- Catalog layout presets (overwrite / cancel) ---------------------------

  # Layout presets are chosen from the preset drawer on the Appearance page.
  # Both scenarios start from a catalog that already holds rows, so choosing
  # a preset has to go through the destructive-overwrite confirmation.
  when_("I select a layout preset such as cinema, learning, or creator", fn world ->
    select_layout_preset_over_existing_rows(world)
  end)

  when_("I select a layout preset", fn world ->
    select_layout_preset_over_existing_rows(world)
  end)

  when_("I confirm the overwrite", fn world ->
    session = world.session
    accept_confirm(session, fn s -> click(s, css("[data-test=overwrite-preset-btn]")) end)
    refute_has(session, css("[data-test=overwrite-preset-btn]"))

    Map.put(world, :session, session)
  end)

  when_("I cancel before confirming the overwrite", fn world ->
    session = world.session
    _message = dismiss_confirm(session, fn s -> click(s, css("[data-test=overwrite-preset-btn]")) end)

    # Dismissing the browser confirm leaves the preview (and its overwrite
    # button) in place.
    assert_has(session, css("[data-test=overwrite-preset-btn]"))
    Map.put(world, :session, session)
  end)

  then_("all existing rows are replaced with the preset configuration", fn world ->
    {:ok, preset} = Presets.get(world.preview_preset)
    %{results: rows} = Catalog.list_rows(world.org)
    row_ids = Enum.map(rows, & &1.id)

    for old_id <- world.existing_row_ids do
      refute old_id in row_ids, "expected pre-existing row #{old_id} to be replaced"
    end

    # A preset row's row_type becomes the catalog row's source_type.
    actual = rows |> Enum.map(&{to_string(&1.source_type), to_string(&1.card_variant)}) |> Enum.sort()
    expected = preset.rows |> Enum.map(&{to_string(&1.row_type), to_string(&1.card_variant)}) |> Enum.sort()

    assert actual == expected,
           "expected the catalog rows to match the #{world.preview_preset} preset"

    assert persisted_preset(world.org) == world.preview_preset
    world
  end)

  then_("my existing catalog rows remain unchanged", fn world ->
    %{results: rows} = Catalog.list_rows(world.org)

    assert Enum.map(rows, &{&1.id, &1.title}) == world.existing_rows,
           "expected the catalog rows to be untouched after cancelling"

    refute persisted_preset(world.org) == world.preview_preset,
           "expected #{world.preview_preset} NOT to be recorded after cancelling"

    world
  end)

  # ---- Accent colour overrides ---------------------------------------------

  when_("I enter custom oklch or hex color values for accent color slots", fn world ->
    session =
      world.session
      |> await_live_connect()
      |> fill_in(css("[data-test=color-input-accent_color_base] input[type=text]"),
        with: @custom_accent_base
      )
      |> fill_accent_variant(:accent_color_hover, @custom_accent_hover, 10)
      |> fill_accent_variant(:accent_color_active, @custom_accent_active, 10)

    accents = %{
      accent_color_base: @custom_accent_base,
      accent_color_hover: @custom_accent_hover,
      accent_color_active: @custom_accent_active
    }

    Map.merge(world, %{session: session, custom_accents: accents})
  end)

  when_("save the appearance settings", fn world ->
    Map.put(world, :session, save_appearance(world.session))
  end)

  when_("save", fn world ->
    Map.put(world, :session, save_appearance(world.session))
  end)

  then_("the CSS variables are updated", fn world ->
    org = Repo.reload!(world.org)

    for {field, value} <- world.custom_accents do
      assert Map.fetch!(org, field) == value,
             "expected #{field} to be saved as #{value}, got #{inspect(Map.fetch!(org, field))}"
    end

    session = visit_viewer_home(world.session, world.org)

    assert root_css_var(session, "--color-accent") == @custom_accent_base
    assert root_css_var(session, "--color-accent-hover") == @custom_accent_hover
    assert root_css_var(session, "--color-accent-active") == @custom_accent_active

    Map.merge(world, %{session: session, org: org})
  end)

  then_("the viewer site uses my custom colors", fn world ->
    session = visit_viewer_home(world.session, world.org)
    host = "[data-test=sv-root]"

    assert probe_style(session, host, "backgroundColor", "var(--sv-accent)") ==
             probe_style(session, host, "backgroundColor", @custom_accent_base),
           "expected the viewer accent (--sv-accent) to use the custom accent colour"

    assert probe_style(session, host, "backgroundColor", "var(--sv-accent-hover)") ==
             probe_style(session, host, "backgroundColor", @custom_accent_hover),
           "expected the viewer hover accent (--sv-accent-hover) to use the custom hover colour"

    Map.put(world, :session, session)
  end)

  # ---- Fonts ---------------------------------------------------------------

  when_("I choose a display font from the approved font list", fn world ->
    assert @display_font in Accounts.Organization.approved_display_fonts()

    session =
      world.session
      |> await_live_connect()
      |> select_option("#organization_display_font", @display_font)

    Map.merge(world, %{session: session, chosen_font: @display_font})
  end)

  when_("I choose a body font from the approved font list", fn world ->
    assert @body_font in Accounts.Organization.approved_body_fonts()

    session =
      world.session
      |> await_live_connect()
      |> select_option("#theme_font_body", @body_font)

    Map.merge(world, %{session: session, chosen_font: @body_font})
  end)

  then_("the viewer site loads that font for headings", fn world ->
    session = visit_viewer_home(world.session, world.org)

    assert_font_stylesheet_loaded(session, world.chosen_font)

    heading_font = root_css_var(session, "--sv-font-heading", "[data-test=sv-root]")

    assert heading_font =~ world.chosen_font,
           "expected viewer headings (--sv-font-heading) to use #{world.chosen_font}, got #{inspect(heading_font)}"

    Map.put(world, :session, session)
  end)

  then_("the viewer site loads that font for body text", fn world ->
    session = visit_viewer_home(world.session, world.org)

    assert_font_stylesheet_loaded(session, world.chosen_font)

    body_font = computed_style(session, "[data-test=sv-root]", "fontFamily")

    assert body_font =~ world.chosen_font,
           "expected viewer body text to use #{world.chosen_font}, got #{inspect(body_font)}"

    Map.put(world, :session, session)
  end)

  # ---- Drawer state across LiveView updates --------------------------------

  @drawer_hover_accent "#1A2B3C"

  when_("I open the accent variants drawer", fn world ->
    session =
      world.session
      |> click(css("[data-test=accent-variants-drawer] summary"))
      |> assert_has(css("[data-test=accent-variants-drawer][open]"))

    Map.put(world, :session, session)
  end)

  when_("I change the hover accent color inside the drawer", fn world ->
    session =
      world.session
      |> fill_in(css("[data-test=color-input-accent_color_hover] input[type=text]"),
        with: @drawer_hover_accent
      )
      # The preview only carries the new hover accent once the server has
      # handled the change and patched the page, so this waits for that
      # LiveView update to land.
      |> assert_has(
        css(
          "[data-test=preview-frame] > div[style*='--color-accent-hover: #{@drawer_hover_accent}']",
          visible: :any
        )
      )

    Map.put(world, :session, session)
  end)

  then_("the accent variants drawer is still open after the preview updates", fn world ->
    assert_has(world.session, css("[data-test=accent-variants-drawer][open]"))

    assert_has(
      world.session,
      css("[data-test=color-input-accent_color_hover] input[type=text]")
    )

    world
  end)

  # ---- Theme propagation ---------------------------------------------------

  given_("I have saved a new theme", fn world ->
    :ok = Events.subscribe(world.org.id)

    # Warm the viewer's cached theme so the assertion below proves the cache
    # was invalidated rather than filled for the first time.
    session = visit_viewer_home(world.session, world.org)
    refute String.downcase(sv_root_style(session)) =~ "--sv-bg-primary: #{@propagated_background}"

    session =
      session
      |> visit_live("/admin/appearance?org=#{world.org.slug}")
      |> fill_in(css(@background_input), with: @propagated_background)
      |> click(css("[data-test=save-branding-btn]"))

    Map.merge(world, %{session: session, saved_background: @propagated_background})
  end)

  when_("the save completes", fn world ->
    assert_has(world.session, css("[role=alert]", text: "Appearance saved."))
    theme = Branding.get_theme_or_default(world.org)
    assert String.downcase(theme.background || "") == world.saved_background
    world
  end)

  then_("a cache invalidation event is broadcast via PubSub", fn world ->
    org_id = world.org.id

    assert_receive {:marquee_event, {event, %{organization_id: ^org_id}}, _scope}
                   when event in [:theme_created, :theme_updated],
                   5_000

    world
  end)

  then_("viewers see the updated theme without a server restart", fn world ->
    session = visit_viewer_home(world.session, world.org)

    assert String.downcase(sv_root_style(session)) =~
             "--sv-bg-primary: #{world.saved_background}",
           "expected the viewer site to render the newly saved background"

    Map.put(world, :session, session)
  end)

  # ---- Full-screen preview overlay -------------------------------------------

  when_("I click the expand preview button", fn world ->
    Map.put(world, :session, expand_preview(world.session))
  end)

  given_("the full-screen preview overlay is open", fn world ->
    session =
      world.session
      |> visit_live("/admin/appearance?org=#{world.org.slug}")
      |> expand_preview()

    Map.put(world, :session, session)
  end)

  then_("a full-screen overlay appears", fn world ->
    overlay = "[data-test=preview-expanded-overlay]"
    assert_has(world.session, css("#{overlay}[role=dialog]"))

    covers_viewport =
      run_js(
        world.session,
        """
        const r = document.querySelector(arguments[0]).getBoundingClientRect();
        return r.left <= 0 && r.top <= 0 &&
          r.width >= window.innerWidth && r.height >= window.innerHeight;
        """,
        [overlay]
      )

    assert covers_viewport, "expected the preview overlay to cover the whole viewport"
    world
  end)

  then_("the overlay renders the canonical hero carousel component", fn world ->
    assert_has(
      world.session,
      css("[data-test=preview-expanded-overlay] [data-test=hero-carousel]#appearance-preview-hero")
    )

    world
  end)

  then_("the CTA buttons in the overlay match the viewer site exactly", fn world ->
    overlay = "[data-test=preview-expanded-overlay]"
    overlay_ctas = hero_cta_snapshot(world.session, overlay)

    assert Map.has_key?(overlay_ctas, "hero-primary-cta-0"),
           "expected the overlay hero to render a primary CTA"

    # The viewer site needs a configured hero slide to render CTAs at all.
    ensure_viewer_hero_slide(world.org)

    viewer = visit_viewer_home(world.session, world.org)
    viewer_ctas = hero_cta_snapshot(viewer, "[data-test=sv-root]")

    assert Map.keys(overlay_ctas) == Map.keys(viewer_ctas),
           "expected the overlay and viewer hero to render the same CTA buttons"

    for {cta, overlay_style} <- overlay_ctas do
      assert overlay_style == Map.fetch!(viewer_ctas, cta),
             "expected #{cta} in the overlay to match the viewer site: " <>
               "#{inspect(overlay_style)} vs #{inspect(Map.fetch!(viewer_ctas, cta))}"
    end

    Map.put(world, :session, viewer)
  end)

  when_("I click the close button on the overlay", fn world ->
    session = click(world.session, css("[data-test=close-preview-expanded]"))
    Map.put(world, :session, session)
  end)

  then_("the overlay is dismissed", fn world ->
    refute_has(world.session, css("[data-test=preview-expanded-overlay]"))
    world
  end)

  then_("I return to the appearance editor", fn world ->
    world.session
    |> assert_has(css("[data-test=branding-editor]"))
    |> assert_has(css("[data-test=preview-frame] [data-test=hero-carousel]"))

    assert current_path(world.session) =~ "/admin/appearance"
    world
  end)

  # ---- Mini preview CTAs ---------------------------------------------------

  then_("the primary CTA in the mini preview uses the hero-cta-primary CSS class", fn world ->
    assert mini_preview_cta_classes(world.session, "hero-primary-cta-0") =~ "hero-cta-primary"
    world
  end)

  then_("the secondary CTA in the mini preview uses the hero-cta-secondary CSS class", fn world ->
    assert mini_preview_cta_classes(world.session, "hero-secondary-cta-0") =~
             "hero-cta-secondary"

    world
  end)

  then_("both CTAs reflect my configured accent color and text-on-accent color", fn world ->
    session = world.session
    host = "[data-test=preview-frame] > div"

    accent_bg = probe_style(session, host, "backgroundColor", "var(--sv-accent)")
    on_accent = probe_style(session, host, "color", "var(--sv-text-on-accent)")

    for cta <- ["hero-primary-cta-0", "hero-secondary-cta-0"] do
      selector = "[data-test=preview-frame] [data-test=#{cta}]"

      assert computed_style(session, selector, "backgroundColor") == accent_bg,
             "expected #{cta} background to use the configured accent colour"

      assert computed_style(session, selector, "color") == on_accent,
             "expected #{cta} text to use the configured text-on-accent colour"
    end

    world
  end)

  # ---- Organization branding: custom domain + admin accent -------------------

  # The settings page is expected to offer a custom-domain field.
  when_("I enter and save a custom domain", fn world ->
    domain = "watch-#{System.unique_integer([:positive])}.example.test"

    session =
      world.session
      |> await_live_connect()
      |> fill_in(css("[data-test=custom-domain-input]"), with: domain)
      |> click(css("[data-test=save-custom-domain-btn]"))

    Map.merge(world, %{session: session, custom_domain: domain})
  end)

  then_("the organization is accessible at that custom domain", fn world ->
    assert {:ok, org} = Accounts.get_organization_by_custom_domain(world.custom_domain)
    assert org.id == world.org.id

    base_url = Application.fetch_env!(:wallaby, :base_url)

    response =
      Req.get!(base_url <> "/",
        headers: [{"host", world.custom_domain}],
        redirect: false,
        retry: false
      )

    assert response.status == 200

    assert response.body =~ ~s(data-tenant="#{world.org.slug}"),
           "expected #{world.custom_domain} to serve #{world.org.slug}'s viewer site"

    world
  end)

  # The appearance editor is expected to offer an admin accent colour input
  # alongside the viewer accent slots.
  when_("I enter a custom color for the admin accent", fn world ->
    session =
      world.session
      |> await_live_connect()
      |> fill_in(css("[data-test=color-input-admin_accent_color] input[type=text]"),
        with: @custom_admin_accent
      )

    Map.merge(world, %{session: session, admin_accent: @custom_admin_accent})
  end)

  then_("the admin dashboard reflects the custom accent color", fn world ->
    assert Repo.reload!(world.org).admin_accent_color == world.admin_accent

    session = visit_live(world.session, "/admin?org=#{world.org.slug}")
    host = "[data-test=admin-nav-dashboard]"

    assert probe_style(session, host, "backgroundColor", "var(--color-admin-accent)") ==
             probe_style(session, host, "backgroundColor", world.admin_accent),
           "expected the admin dashboard accent (--color-admin-accent) to use #{world.admin_accent}"

    Map.put(world, :session, session)
  end)

  # ---- Shared branding helpers -----------------------------------------------

  defp select_layout_preset_over_existing_rows(world) do
    row = insert(:row, organization: world.org, title: "Existing Row", visible: true, position: 0)
    %{results: rows} = Catalog.list_rows(world.org)
    assert Enum.any?(rows, &(&1.id == row.id))

    session =
      world.session
      |> visit_live("/admin/appearance?org=#{world.org.slug}")
      |> select_preset(@preview_preset_name)
      |> assert_has(css("[data-test=overwrite-preset-btn]"))

    Map.merge(world, %{
      session: session,
      preview_preset: @preview_preset_name,
      existing_rows: Enum.map(rows, &{&1.id, &1.title}),
      existing_row_ids: Enum.map(rows, & &1.id)
    })
  end

  defp save_appearance(session) do
    session
    |> click(css("[data-test=save-branding-btn]"))
    |> assert_has(css("[role=alert]", text: "Appearance saved."))
  end

  defp expand_preview(session) do
    session
    |> await_live_connect()
    |> click(css("[data-test=expand-preview-btn]"))
    |> assert_has(css("[data-test=preview-expanded-overlay]"))
  end

  defp visit_viewer_home(session, org) do
    session
    |> visit("/?org=#{org.slug}&preview=member")
    |> assert_has(css("[data-test=sv-root]"))
  end

  defp sv_root_style(session) do
    session
    |> find(css("[data-test=sv-root]"))
    |> Element.attr("style")
    |> Kernel.||("")
  end

  defp assert_font_stylesheet_loaded(session, font) do
    family = String.replace(font, " ", "+")

    assert_has(
      session,
      css("link[rel=stylesheet][href*='fonts.googleapis.com'][href*='family=#{family}']",
        visible: false,
        minimum: 1
      )
    )
  end

  defp mini_preview_cta_classes(session, cta) do
    session
    |> find(css("[data-test=preview-frame] [data-test=#{cta}]", visible: :any))
    |> Element.attr("class")
  end

  defp ensure_viewer_hero_slide(org) do
    if Catalog.resolve_hero_slides(org).slides == [] do
      hero_row = insert(:hero_row, organization: org, visible: true)

      video =
        insert(:video,
          organization: org,
          title: "Overlay CTA Video",
          mux_status: "ready",
          published: true
        )

      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)
    end

    :ok
  end

  # Returns %{"hero-primary-cta-0" => %{prop => value}, ...} for the first
  # hero slide's CTA buttons inside `host`.
  defp hero_cta_snapshot(session, host) do
    run_js(
      session,
      """
      const host = document.querySelector(arguments[0]);
      const props = arguments[1];
      const out = {};
      host.querySelectorAll('[data-test=hero-primary-cta-0], [data-test=hero-secondary-cta-0]')
        .forEach((el) => {
          const cs = getComputedStyle(el);
          const style = {className: el.className};
          props.forEach((p) => { style[p] = cs[p]; });
          out[el.getAttribute('data-test')] = style;
        });
      return out;
      """,
      [host, @cta_style_props]
    )
  end

  defp root_css_var(session, var, selector \\ "html") do
    run_js(
      session,
      "return getComputedStyle(document.querySelector(arguments[0])).getPropertyValue(arguments[1]).trim();",
      [selector, var]
    )
  end

  defp computed_style(session, selector, prop) do
    run_js(
      session,
      "return getComputedStyle(document.querySelector(arguments[0]))[arguments[1]];",
      [selector, prop]
    )
  end

  # Paints a throwaway element inside `host_selector` with `value` assigned
  # to `prop` and returns the browser's computed value, so CSS variables and
  # literal colours can be compared in one normalised form.
  defp probe_style(session, host_selector, prop, value) do
    run_js(
      session,
      """
      const host = document.querySelector(arguments[0]) || document.body;
      const probe = document.createElement('span');
      probe.style[arguments[1]] = arguments[2];
      host.appendChild(probe);
      const computed = getComputedStyle(probe)[arguments[1]];
      probe.remove();
      return computed;
      """,
      [host_selector, prop, value]
    )
  end

  defp run_js(session, script, args) do
    me = self()
    ref = make_ref()
    execute_script(session, script, args, fn value -> send(me, {ref, value}) end)

    receive do
      {^ref, value} -> value
    after
      5_000 -> flunk("browser script returned no value")
    end
  end

  # The "Accent variants" <details> renders without an `open` attribute, so a
  # LiveView patch from the form's phx-change can collapse it while the
  # operator types; they reopen it and continue. Each fill is retried and
  # then read back from the input.
  defp fill_accent_variant(session, field, value, 0) do
    session
    |> click_open_accent_drawer()
    |> fill_in(css("[data-test=color-input-#{field}] input[type=text]"), with: value)
    |> assert_accent_value(field, value)
  end

  defp fill_accent_variant(session, field, value, attempts) do
    try do
      session
      |> click_open_accent_drawer()
      |> fill_in(css("[data-test=color-input-#{field}] input[type=text]"), with: value)
      |> assert_accent_value(field, value)
    rescue
      _ in [Wallaby.QueryError, Wallaby.ExpectationNotMetError, ExUnit.AssertionError] ->
        fill_accent_variant(session, field, value, attempts - 1)
    end
  end

  defp click_open_accent_drawer(session) do
    if has?(session, css("[data-test=accent-variants-drawer][open]")) do
      session
    else
      click(session, css("[data-test=accent-variants-drawer] summary"))
    end
  end

  defp assert_accent_value(session, field, value) do
    actual =
      session
      |> find(css("[data-test=color-input-#{field}] input[type=text]", visible: :any))
      |> Element.value()

    assert actual == value
    session
  end

  # Wallaby's refute_has/2 checks once and fails while an element is still
  # leaving the DOM after a LiveView patch. Asserting a count of zero retries
  # until the element is gone (or the query times out).
  defp refute_has(parent, query), do: assert_has(parent, Wallaby.Query.count(query, 0))
end
