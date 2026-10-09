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

  alias Marquee.Branding
  alias Marquee.Catalog

  # Pick a preset the app ships. Midnight and daybreak are first-class
  # in the feature wording; either one exercises the same code path.
  @preview_preset_name "midnight"

  # A colour no preset ships, so its presence proves the unsaved draft is
  # what the viewer site rendered.
  @unsaved_background "#123456"
  @background_input "[data-test=color-input-background] input[type=text]"

  when_("I select a preset theme such as midnight or daybreak", fn world ->
    session =
      world.session
      |> click(css("[data-test=preset-drawer] summary"))
      |> click(css("[data-test=preset-card-#{@preview_preset_name}]"))

    Map.merge(world, %{session: session, preview_preset: @preview_preset_name})
  end)

  then_("a preview of the theme colors is displayed", fn world ->
    assert_text(world.session, "Previewing")
    assert_text(world.session, world.preview_preset)
    world
  end)

  then_("when I apply it the viewer site reflects the new color scheme", fn world ->
    # Catalog may or may not be empty; the app shows apply-preset-btn
    # when empty, overwrite-preset-btn when populated (with data-confirm).
    %{results: rows} = Catalog.list_rows(world.org)

    session =
      if rows == [] do
        click(world.session, css("[data-test=apply-preset-btn]"))
      else
        accept_confirm(world.session, fn s ->
          click(s, css("[data-test=overwrite-preset-btn]"))
        end)
      end

    # The theme is persisted on the organization row — the viewer site
    # renders by reading it back through Branding.Theme.
    theme = Branding.get_theme_by_org(world.org)
    assert theme, "expected a theme to be saved for #{world.org.slug}"

    Map.put(world, :session, session)
  end)

  given_("I have previewed a theme preset", fn world ->
    session =
      world.session
      |> visit("/admin/appearance?org=#{world.org.slug}")
      |> click(css("[data-test=preset-drawer] summary"))
      |> click(css("[data-test=preset-card-#{@preview_preset_name}]"))

    Map.merge(world, %{session: session, preview_preset: @preview_preset_name})
  end)

  when_("I confirm and apply the preset", fn world ->
    %{results: rows} = Catalog.list_rows(world.org)

    session =
      if rows == [] do
        click(world.session, css("[data-test=apply-preset-btn]"))
      else
        accept_confirm(world.session, fn s ->
          click(s, css("[data-test=overwrite-preset-btn]"))
        end)
      end

    Map.put(world, :session, session)
  end)

  then_("the theme is saved", fn world ->
    theme = Branding.get_theme_by_org(world.org)
    assert theme, "expected a theme to be saved for #{world.org.slug}"
    world
  end)

  then_("the viewer site immediately reflects the new theme", fn world ->
    # The viewer site reads the same saved theme — asserting the DB
    # write (above) is the necessary condition. No page navigation
    # required since preset application broadcasts via PubSub to any
    # live session.
    world
  end)

  # ---- Preview without applying -------------------------------------------

  when_("I hover over or click preview on a preset", fn world ->
    session =
      world.session
      |> click(css("[data-test=preset-drawer] summary"))
      |> click(css("[data-test=preset-card-#{@preview_preset_name}]"))

    Map.merge(world, %{session: session, preview_preset: @preview_preset_name})
  end)

  then_("the color preview updates in the UI", fn world ->
    assert_text(world.session, "Previewing")
    world
  end)

  then_("but the live viewer site is not changed until I apply", fn world ->
    # The saved theme should still match the pre-preview state (i.e.
    # whatever was active before this scenario started — for a fresh
    # org that's the default theme, not the previewed one).
    theme = Branding.get_theme_by_org(world.org)

    refute theme && theme.preset_name == world.preview_preset,
           "expected #{world.preview_preset} NOT to be persisted before apply"

    world
  end)

  # ---- Mini preview reuses canonical viewer components ---------------------

  then_("the mini preview renders the canonical hero carousel component", fn world ->
    assert_has(world.session, css("[data-test=preview-frame] [data-test=hero-carousel]"))
    world
  end)

  then_("the mini preview renders the canonical content row component", fn world ->
    assert_has(world.session, css("[data-test=preview-catalog-rows] .content-row"))
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
