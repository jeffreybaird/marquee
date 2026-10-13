defmodule MarqueeFeatures.Steps.Branding do
  @moduledoc """
  Step definitions for branding.feature.

  Covers preset selection + apply flows on the appearance page. Custom
  color overrides, font pickers, theme-propagation, and custom domain
  scenarios stay undefined — they need either deeper form mapping or
  infra that sits outside Wallaby's reach (DNS).
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import ExUnit.Assertions
  import Marquee.Factory
  import MarqueeFeatures.Support.Browser

  alias Marquee.Catalog
  alias Marquee.Catalog.Presets

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

    assert Enum.sort(Enum.map(rows, & &1.row_type)) ==
             Enum.sort(Enum.map(preset.rows, & &1.row_type)),
           "expected the catalog rows to be seeded from the #{world.preview_preset} preset"

    world
  end)

  # ---- Preview without applying -------------------------------------------

  when_("I hover over or click preview on a preset", fn world ->
    session = select_preset(world.session, @preview_preset_name)
    Map.merge(world, %{session: session, preview_preset: @preview_preset_name})
  end)

  then_("but the catalog layout is not changed until I apply", fn world ->
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
    |> assert_has(css("[data-test=preset-picker]", text: "Previewing #{name}"))
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
      session
      |> accept_confirm(fn s -> click(s, css("[data-test=overwrite-preset-btn]")) end)
      |> refute_has(css("[data-test=overwrite-preset-btn]"))
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
      assert_has(world.session, css("[data-test=preview-catalog-rows] img[src*='picsum.photos']"))
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
end
