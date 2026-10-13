defmodule MarqueeFeatures.Steps.Catalog do
  @moduledoc """
  Step definitions for the catalog features: hero banner management,
  homepage row management, and row card display options.

  Operator actions drive the admin Catalog UI (`/admin/catalog`) through
  Wallaby. Viewer-facing assertions load the member preview of the viewer
  home (`/?org=<slug>&preview=member`), which renders the same
  `viewer_home_body` component a signed-in member sees.

  Row reorder still uses the `Catalog.reorder_rows/2` context call because
  drag-and-drop is handled client-side via a Hook and is not easily
  simulated in a headless browser.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Browser, except: [refute_has: 2]
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser

  alias Marquee.Catalog
  alias Marquee.Catalog.HeroSlide
  alias Marquee.Catalog.Row
  alias Marquee.Repo

  # Served by the app itself so the browser renders them (an unreachable
  # external URL leaves an alt="" image with no size, which Wallaby treats
  # as invisible).
  @title_logo_url "/images/logo.svg"
  @channel_logo_url "/images/primary-mark.svg"
  @banner_image_fixture "hero-banner.png"

  # ---- Create row ---------------------------------------------------------

  when_ "I create a new row with a title and variant type", fn world ->
    title = "Featured Videos #{System.unique_integer([:positive])}"

    session =
      world.session
      |> visit("/admin/catalog?org=#{world.org.slug}")
      |> click(css("[data-test=new-row-btn]"))
      |> fill_in(css("[data-test=row-title-input]"), with: title)
      |> click(button("Save"))

    Map.merge(world, %{session: session, new_row_title: title})
  end

  then_ "the row appears in the catalog list", fn world ->
    session = visit(world.session, "/admin/catalog?org=#{world.org.slug}")
    assert_text(session, world.new_row_title)
    Map.put(world, :session, session)
  end

  # ---- Reorder rows -------------------------------------------------------

  given_ "the catalog has multiple rows", fn world ->
    org = world.org
    row_a = insert(:row, organization: org, title: "Row A", position: 0)
    row_b = insert(:row, organization: org, title: "Row B", position: 1)
    row_c = insert(:row, organization: org, title: "Row C", position: 2)
    Map.put(world, :rows, [row_a, row_b, row_c])
  end

  # Drag-and-drop is a Phoenix LiveView Hook — simulating it in Wallaby would
  # require dispatching the exact pointer event sequence the Sortable hook
  # expects. The context call here is a pragmatic gap; swap in a real drag
  # once you need to guard against hook regressions.
  when_ "I move a row up or down", fn world ->
    new_order = world.rows |> Enum.reverse() |> Enum.map(& &1.id)
    :ok = Catalog.reorder_rows(world.scope, new_order)
    Map.put(world, :new_order, new_order)
  end

  then_ "the display order on the viewer homepage updates accordingly", fn world ->
    %{results: rows} = Catalog.list_rows(world.org)
    actual_ids = Enum.map(rows, & &1.id)
    assert actual_ids == world.new_order
    world
  end

  # ---- Row fixtures -------------------------------------------------------

  given_ "a catalog row exists", fn world ->
    world
    |> put_row_with_videos("Existing Row", 1, [])
    |> reload_catalog()
  end

  given_ "a catalog row has videos", fn world ->
    world
    |> put_row_with_videos("Row With Videos", 2, [])
    |> reload_catalog()
  end

  given_ "a catalog row is hidden", fn world ->
    world
    |> put_row_with_videos("Hidden Row", 1, visible: false)
    |> reload_catalog()
  end

  given_ "a catalog row exists with \"Show details below card\" enabled", fn world ->
    world
    |> put_row_with_videos("Details Row", 1, show_details: true, title_overlay: false)
    |> reload_catalog()
  end

  given_ "a catalog row has details hidden", fn world ->
    world
    |> put_row_with_videos("No Details Row", 1, show_details: false, title_overlay: false)
    |> reload_catalog()
  end

  given_ "the catalog has two rows", fn world ->
    {first, first_videos} = insert_row_with_videos(world.org, "First Row", 1, position: 0)
    {second, second_videos} = insert_row_with_videos(world.org, "Second Row", 1, position: 1)

    world
    |> Map.put(:changed_row, first)
    |> Map.put(:other_row, second)
    |> Map.put(:row_videos_by_row, %{first.id => first_videos, second.id => second_videos})
    |> reload_catalog()
  end

  # ---- Row actions --------------------------------------------------------

  when_ "I add videos to that row", fn world ->
    videos =
      for n <- 1..2 do
        insert(:video,
          organization: world.org,
          title: "Added Video #{n} #{System.unique_integer([:positive])}",
          mux_status: "ready",
          published: true
        )
      end

    session =
      world.session
      |> open_row_items(world.row)
      |> click(css("[data-test=add-videos-btn]"))

    session =
      Enum.reduce(videos, session, fn video, session ->
        add_button = css("button[phx-click=add_video_to_row][phx-value-video-id='#{video.id}']")

        session =
          if has?(session, add_button),
            do: session,
            else: click(session, css("[data-test=add-videos-btn]"))

        session
        |> click(add_button)
        |> assert_has(css("button[phx-click=remove_video_from_row][phx-value-video-id='#{video.id}']"))
      end)

    Map.merge(world, %{session: session, added_videos: videos})
  end

  then_ "those videos appear in the row on the viewer homepage", fn world ->
    session = visit_viewer_home(world)

    for video <- world.added_videos do
      assert_has(
        session,
        css("[data-test=content-row-#{world.row.id}] [data-test=sv-card-#{video.id}]")
      )
    end

    Map.put(world, :session, session)
  end

  when_ "I remove a video from the row", fn world ->
    [removed | _] = world.row_videos
    remove_button = css("button[phx-click=remove_video_from_row][phx-value-video-id='#{removed.id}']")

    session =
      world.session
      |> open_row_items(world.row)
      |> click(remove_button)
      |> refute_has(remove_button)

    Map.merge(world, %{session: session, removed_video: removed})
  end

  then_ "that video no longer appears in the row", fn world ->
    [_removed | kept] = world.row_videos
    session = visit_viewer_home(world)
    row_css = "[data-test=content-row-#{world.row.id}]"

    for video <- kept, do: assert_has(session, css("#{row_css} [data-test=sv-card-#{video.id}]"))
    refute_has(session, css("#{row_css} [data-test=sv-card-#{world.removed_video.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I toggle the row visibility off", fn world ->
    session = toggle_row_visibility(world.session, world.row, "Hidden")
    Map.put(world, :session, session)
  end

  then_ "viewers no longer see that row on the homepage", fn world ->
    session = visit_viewer_home(world)
    refute_has(session, css("[data-test=content-row-#{world.row.id}]"))
    Map.put(world, :session, session)
  end

  then_ "viewers see the row on the homepage", fn world ->
    session = visit_viewer_home(world)

    assert_has(
      session,
      css("[data-test=content-row-#{world.row.id}]", text: world.row.title)
    )

    Map.put(world, :session, session)
  end

  when_ "I edit the row title and save", fn world ->
    new_title = "Renamed Row #{System.unique_integer([:positive])}"

    session =
      world.session
      |> open_row_editor(world.row)
      |> fill_in(css("[data-test=row-title-input]"), with: new_title)
      |> save_row_form()

    Map.merge(world, %{session: session, new_row_title: new_title})
  end

  then_ "the updated title appears on the viewer homepage", fn world ->
    session = visit_viewer_home(world)

    assert_has(
      session,
      css("[data-test=content-row-#{world.row.id}]", text: world.new_row_title)
    )

    Map.put(world, :session, session)
  end

  when_ "I delete the row", fn world ->
    session = await_live_connect(world.session)
    accept_confirm(session, fn s -> click(s, css("[data-test=delete-row-#{world.row.id}]")) end)

    refute_has(session, css("[data-test=row-#{world.row.id}]"))
    Map.put(world, :session, session)
  end

  then_ "it is removed from the catalog", fn world ->
    row = Repo.get!(Row, world.row.id)
    assert row.deleted_at, "expected row #{world.row.id} to be soft-deleted"

    %{results: rows} = Catalog.list_rows(world.org)

    refute Enum.any?(rows, &(&1.id == world.row.id)),
           "expected row #{world.row.id} to be absent from the catalog list"

    world
  end

  then_ "viewers no longer see it", fn world ->
    session = visit_viewer_home(world)
    refute_has(session, css("[data-test=content-row-#{world.row.id}]"))
    Map.put(world, :session, session)
  end

  # ---- Row card display options -------------------------------------------

  when_ "I uncheck \"Show details below card\" for that row and save", fn world ->
    session =
      world.session
      |> open_row_editor(world.row)
      |> assert_has(css("[data-test=row-show-details-input]:checked"))
      |> click(css("[data-test=row-show-details-input]"))
      |> save_row_form()

    Map.put(world, :session, session)
  end

  when_ "I check \"Show details below card\" for that row and save", fn world ->
    session =
      world.session
      |> open_row_editor(world.row)
      |> refute_has(css("[data-test=row-show-details-input]:checked"))
      |> click(css("[data-test=row-show-details-input]"))
      |> save_row_form()

    Map.put(world, :session, session)
  end

  when_ "I check \"Overlay title on thumbnail\" for that row and save", fn world ->
    session =
      world.session
      |> open_row_editor(world.row)
      |> click(css("[data-test=row-title-overlay-input]"))
      |> save_row_form()

    Map.put(world, :session, session)
  end

  when_ "I view the row editor", fn world ->
    session = open_row_editor(world.session, world.row)
    Map.put(world, :session, session)
  end

  when_ "I hide details and enable overlay on only one row", fn world ->
    session =
      world.session
      |> open_row_editor(world.changed_row)
      |> click(css("[data-test=row-show-details-input]"))
      |> click(css("[data-test=row-title-overlay-input]"))
      |> save_row_form()

    Map.put(world, :session, session)
  end

  then_ "cards in that row on the viewer homepage display without the details bar", fn world ->
    [video] = world.row_videos
    session = visit_viewer_home(world)
    card = "[data-test=content-row-#{world.row.id}] [data-test=sv-card-#{video.id}]"

    assert_has(session, css(card))
    refute_has(session, css("#{card} [data-test=sv-card-favorite-#{video.id}]"))
    Map.put(world, :session, session)
  end

  then_ "cards in that row display the details bar again", fn world ->
    [video] = world.row_videos
    session = visit_viewer_home(world)
    card = "[data-test=content-row-#{world.row.id}] [data-test=sv-card-#{video.id}]"

    assert_has(session, css("#{card} [data-test=sv-card-favorite-#{video.id}]"))
    Map.put(world, :session, session)
  end

  then_ "cards in that row show the title text overlaid on the thumbnail", fn world ->
    [video] = world.row_videos
    session = visit_viewer_home(world)
    card = "[data-test=content-row-#{world.row.id}] [data-test=sv-card-#{video.id}]"

    assert_has(
      session,
      css("#{card} [data-test=sv-card-title-overlay-#{video.id}]", text: video.title)
    )

    Map.put(world, :session, session)
  end

  then_ "the \"Overlay title on thumbnail\" checkbox is not visible", fn world ->
    world.session
    |> assert_has(css("[data-test=row-form] [data-test=row-show-details-input]:checked"))
    |> refute_has(css("[data-test=row-title-overlay-input]"))
    |> refute_has(css("[data-test=row-title-overlay-wrapper]"))

    world
  end

  then_ "the other row still displays the details bar and no overlay", fn world ->
    [changed_video] = Map.fetch!(world.row_videos_by_row, world.changed_row.id)
    [other_video] = Map.fetch!(world.row_videos_by_row, world.other_row.id)

    other = Repo.get!(Row, world.other_row.id)
    assert other.show_details, "expected the untouched row to keep show_details enabled"
    refute other.title_overlay, "expected the untouched row to keep title_overlay disabled"

    session = visit_viewer_home(world)
    changed_card = "[data-test=content-row-#{world.changed_row.id}]"
    other_card = "[data-test=content-row-#{world.other_row.id}]"

    # The edited row did change, so the comparison below is meaningful.
    assert_has(session, css("#{changed_card} [data-test=sv-card-title-overlay-#{changed_video.id}]"))

    assert_has(session, css("#{other_card} [data-test=sv-card-favorite-#{other_video.id}]"))
    refute_has(session, css("#{other_card} [data-test=sv-card-title-overlay-#{other_video.id}]"))

    Map.put(world, :session, session)
  end

  # ---- Hero fixtures ------------------------------------------------------

  given_ "a hero slide exists", fn world ->
    world
    |> put_hero_slides(1)
    |> reload_catalog()
  end

  given_ "a hero slide exists with no title logo or channel logo URL", fn world ->
    world = put_hero_slides(world, 1)
    [slide] = world.hero_slides
    assert is_nil(slide.title_logo_url) and is_nil(slide.channel_logo_url)
    reload_catalog(world)
  end

  given_ "the hero has multiple slides", fn world ->
    world
    |> put_hero_slides(3)
    |> reload_catalog()
  end

  given_ "the hero banner is configured", fn world ->
    world
    |> put_hero_slides(2)
    |> reload_catalog()
  end

  given_ "the hero banner is visible", fn world ->
    world = world |> put_hero_slides(1) |> reload_catalog()

    assert_has(world.session, css("[data-test=hero-visibility-toggle]", text: "Visible"))
    world
  end

  # ---- Hero actions -------------------------------------------------------

  when_ "I add a hero slide with a linked video and display metadata", fn world ->
    video =
      insert(:video,
        organization: world.org,
        title: "Hero Feature #{System.unique_integer([:positive])}",
        mux_status: "ready",
        published: true
      )

    headline = "Premiere Night #{System.unique_integer([:positive])}"
    subheadline = "Streaming from Friday"

    session =
      world.session
      |> visit_live("/admin/catalog?org=#{world.org.slug}")
      |> click(css("[data-test=create-hero-btn]"))
      |> click(css("[data-test=hero-add-slide-btn]"))
      |> click(css("div:has(> [data-test=hero-video-select-#{video.id}]) > button"))
      |> fill_in(css("[data-test=hero-headline-input-0]"), with: headline)
      |> fill_in(css("[data-test=hero-subheadline-input-0]"), with: subheadline)
      |> click(css("[data-test=hero-slide-save-btn-0]"))
      |> assert_has(css("[data-test=hero-slide-save-success-0]", text: "Saved"))

    Map.merge(world, %{
      session: session,
      hero_video: video,
      hero_headline: headline,
      hero_subheadline: subheadline
    })
  end

  then_ "the slide appears in the hero banner rotation on the viewer homepage", fn world ->
    session = visit_viewer_home(world)

    session
    |> assert_has(css("[data-test=hero-carousel] [data-test=hero-content-0]", text: world.hero_headline))
    |> assert_has(css("[data-test=hero-content-0]", text: world.hero_subheadline))

    assert hero_cta_href(session, 0) == "/watch/#{world.hero_video.id}"
    Map.put(world, :session, session)
  end

  # The catalog editor only offers a "Custom Background URL" text field for
  # a slide; this step looks for a file input inside the slide editor, as an
  # operator uploading an image would.
  when_ "I upload a banner image for that slide", fn world ->
    image_path = write_banner_image_fixture()

    session =
      world.session
      |> expand_hero_slide(0)
      |> attach_file(css("[data-test=hero-slide-editor-0] input[type=file]"), path: image_path)
      |> click(css("[data-test=hero-slide-save-btn-0]"))
      |> assert_has(css("[data-test=hero-slide-save-success-0]", text: "Saved"))

    Map.put(world, :session, session)
  end

  then_ "the image displays as the slide background", fn world ->
    [slide] = world.hero_slides
    saved = Repo.get!(HeroSlide, slide.id)

    assert is_binary(saved.background_image_url) and saved.background_image_url != "",
           "expected the uploaded banner image to be stored as the slide background"

    session = visit_viewer_home(world)
    image = find(session, css("[data-test=hero-slide-0] img", visible: false, at: 0))
    assert Element.attr(image, "src") == saved.background_image_url
    Map.put(world, :session, session)
  end

  when_ "I reorder the slides", fn world ->
    [first, second, third] = world.hero_slides

    session =
      world.session
      |> expand_hero_slide(1)
      |> click(css("[data-test=hero-slide-editor-1] button[phx-click=move_hero_slide_up]"))

    expected = [second, first, third]

    assert_has(
      session,
      css("[data-test=hero-slide-editor-0] button[phx-click=expand_hero_slide]",
        text: second.headline
      )
    )

    Map.merge(world, %{session: session, expected_hero_order: Enum.map(expected, & &1.video_id)})
  end

  then_ "they rotate in the new order for viewers", fn world ->
    session = visit_viewer_home(world)

    actual =
      world.expected_hero_order
      |> Enum.with_index()
      |> Enum.map(fn {_video_id, index} -> hero_cta_href(session, index) end)

    assert actual == Enum.map(world.expected_hero_order, &"/watch/#{&1}")
    Map.put(world, :session, session)
  end

  when_ "I set an auto-advance interval in milliseconds", fn world ->
    session =
      world.session
      |> await_live_connect()
      |> select_option("[data-test=hero-auto-advance-select]", "10000")
      |> click(css("[data-test=hero-auto-advance-save-btn]"))
      |> assert_has(css("[data-test=hero-auto-advance-save-success]"))

    Map.merge(world, %{session: session, auto_advance_ms: 10_000})
  end

  then_ "slides advance at that pace on the viewer homepage", fn world ->
    session = visit_viewer_home(world)
    carousel = find(session, css("[data-test=hero-carousel]"))
    assert Element.attr(carousel, "data-auto-advance") == Integer.to_string(world.auto_advance_ms)
    Map.put(world, :session, session)
  end

  when_ "I toggle hero visibility off", fn world ->
    session =
      world.session
      |> await_live_connect()
      |> click(css("[data-test=hero-visibility-toggle]"))
      |> assert_has(css("[data-test=hero-visibility-toggle]", text: "Hidden"))

    Map.put(world, :session, session)
  end

  then_ "the hero banner is hidden from viewers", fn world ->
    session = visit_viewer_home(world)
    assert_has(session, css("[data-test=sv-root]"))
    refute_has(session, css("[data-test=hero-carousel]"))
    Map.put(world, :session, session)
  end

  when_ "I delete the slide", fn world ->
    [slide] = world.hero_slides

    session =
      world.session
      |> expand_hero_slide(0)
      |> click(css("[data-test=hero-remove-slide-0]"))
      |> refute_has(css("[data-test=hero-slide-editor-0]"))

    Map.merge(world, %{session: session, deleted_slide: slide})
  end

  then_ "it is removed from the hero rotation", fn world ->
    slide = Repo.get!(HeroSlide, world.deleted_slide.id)
    assert slide.deleted_at, "expected hero slide #{slide.id} to be soft-deleted"

    session = visit_viewer_home(world)
    assert_has(session, css("[data-test=sv-root]"))

    refute_has(
      session,
      css("[data-test=hero-carousel] a[href='/watch/#{world.deleted_slide.video_id}']",
        visible: false
      )
    )

    Map.put(world, :session, session)
  end

  when_ "I enter a title logo URL for that slide", fn world ->
    session =
      world.session
      |> expand_hero_slide(0)
      |> fill_in(css("[data-test=hero-title-logo-url-input-0]"), with: @title_logo_url)
      |> click(css("[data-test=hero-slide-save-btn-0]"))
      |> assert_has(css("[data-test=hero-slide-save-success-0]", text: "Saved"))

    Map.put(world, :session, session)
  end

  then_ "the viewer hero renders the title logo image instead of plain text", fn world ->
    session = visit_viewer_home(world)
    logo = find(session, css("[data-test=hero-title-logo-0]"))
    assert URI.parse(Element.attr(logo, "src")).path == @title_logo_url
    refute_has(session, css("[data-test=hero-content-0] h1"))
    Map.put(world, :session, session)
  end

  when_ "I enter a channel logo URL for that slide", fn world ->
    session =
      world.session
      |> expand_hero_slide(0)
      |> fill_in(css("[data-test=hero-channel-logo-url-input-0]"), with: @channel_logo_url)
      |> click(css("[data-test=hero-slide-save-btn-0]"))
      |> assert_has(css("[data-test=hero-slide-save-success-0]", text: "Saved"))

    Map.put(world, :session, session)
  end

  then_ "the viewer hero renders the channel logo above the title area", fn world ->
    [slide] = world.hero_slides
    session = visit_viewer_home(world)

    channel_logo = find(session, css("[data-test=hero-channel-logo-0]"))
    assert URI.parse(Element.attr(channel_logo, "src")).path == @channel_logo_url

    title = find(session, css("[data-test=hero-content-0] h1", text: slide.headline))
    {_x, logo_y} = Element.location(channel_logo)
    {_x, title_y} = Element.location(title)
    assert logo_y < title_y, "expected the channel logo to sit above the title"

    Map.put(world, :session, session)
  end

  when_ "a viewer sees the hero banner", fn world ->
    session = visit_viewer_home(world)
    assert_has(session, css("[data-test=hero-carousel]"))
    Map.put(world, :session, session)
  end

  then_ "the slide renders the text title and no logo images", fn world ->
    [slide] = world.hero_slides

    world.session
    |> assert_has(css("[data-test=hero-content-0] h1", text: slide.headline))
    |> refute_has(css("[data-test=hero-title-logo-0]"))
    |> refute_has(css("[data-test=hero-channel-logo-0]"))

    world
  end

  when_ "I set only a channel logo URL and leave the title logo URL blank", fn world ->
    session =
      world.session
      |> expand_hero_slide(0)
      |> fill_in(css("[data-test=hero-channel-logo-url-input-0]"), with: @channel_logo_url)
      |> fill_in(css("[data-test=hero-title-logo-url-input-0]"), with: "")
      |> click(css("[data-test=hero-slide-save-btn-0]"))
      |> assert_has(css("[data-test=hero-slide-save-success-0]", text: "Saved"))

    Map.put(world, :session, session)
  end

  then_ "the channel logo appears and the text headline is used for the title", fn world ->
    [slide] = world.hero_slides
    session = visit_viewer_home(world)

    channel_logo = find(session, css("[data-test=hero-channel-logo-0]"))
    assert URI.parse(Element.attr(channel_logo, "src")).path == @channel_logo_url

    session
    |> assert_has(css("[data-test=hero-content-0] h1", text: slide.headline))
    |> refute_has(css("[data-test=hero-title-logo-0]"))

    Map.put(world, :session, session)
  end

  # ---- Private helpers ----------------------------------------------------

  defp visit_viewer_home(world) do
    world.session
    |> visit("/?org=#{world.org.slug}&preview=member")
    |> assert_has(css("[data-test=sv-root]"))
  end

  defp reload_catalog(world) do
    session = visit_live(world.session, "/admin/catalog?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  defp put_row_with_videos(world, title, video_count, row_opts) do
    {row, videos} = insert_row_with_videos(world.org, title, video_count, row_opts)

    world
    |> Map.put(:row, row)
    |> Map.put(:row_videos, videos)
    |> Map.update(:row_videos_by_row, %{row.id => videos}, &Map.put(&1, row.id, videos))
  end

  # Rows only reach the viewer home when they hold at least one item, so
  # every row fixture carries published, playable videos.
  defp insert_row_with_videos(org, title, video_count, row_opts) do
    attrs =
      Keyword.merge(
        [
          organization: org,
          title: "#{title} #{System.unique_integer([:positive])}",
          source_type: :curated,
          visible: true
        ],
        row_opts
      )

    row = insert(:row, attrs)

    videos =
      for n <- 1..video_count do
        video =
          insert(:video,
            organization: org,
            title: "#{title} Video #{n} #{System.unique_integer([:positive])}",
            mux_status: "ready",
            published: true
          )

        insert(:row_item, organization: org, row: row, video: video, position: n - 1)
        video
      end

    {row, videos}
  end

  defp open_row_items(session, row) do
    session
    |> await_live_connect()
    |> click(css("[data-test=row-#{row.id}] button[phx-click=manage_items]"))
    |> assert_has(css("[data-test=add-videos-btn]"))
  end

  defp open_row_editor(session, row) do
    session
    |> await_live_connect()
    |> click(css("[data-test=row-#{row.id}] button[phx-click=edit_row]"))
    |> assert_has(css("[data-test=row-form]"))
  end

  defp save_row_form(session) do
    session
    |> click(css("[data-test=row-form] button[type=submit]"))
    |> refute_has(css("[data-test=row-form]"))
  end

  defp toggle_row_visibility(session, row, expected_label) do
    toggle = "[data-test=row-#{row.id}] [data-test=row-visibility-toggle]"

    session
    |> await_live_connect()
    |> click(css(toggle))
    |> assert_has(css(toggle, text: expected_label))
  end

  defp put_hero_slides(world, count) do
    hero_row = insert(:hero_row, organization: world.org, visible: true)

    slides =
      for position <- 0..(count - 1) do
        video =
          insert(:video,
            organization: world.org,
            title: "Hero Video #{position} #{System.unique_integer([:positive])}",
            mux_status: "ready",
            published: true
          )

        insert(:hero_slide,
          organization: world.org,
          row: hero_row,
          video: video,
          position: position,
          headline: "Hero Headline #{position} #{System.unique_integer([:positive])}"
        )
      end

    Map.merge(world, %{hero_row: hero_row, hero_slides: slides})
  end

  # The slide editor is an accordion: only the expanded slide renders its
  # form and action buttons.
  defp expand_hero_slide(session, position) do
    session = await_live_connect(session)

    if has?(session, css("[data-test=hero-headline-input-#{position}]")) do
      session
    else
      session
      |> click(css("[data-test=hero-slide-editor-#{position}] button[phx-click=expand_hero_slide]"))
      |> assert_has(css("[data-test=hero-headline-input-#{position}]"))
    end
  end

  # Inactive slides are hidden visually, so read the CTA link attribute
  # rather than its rendered text.
  defp hero_cta_href(session, index) do
    session
    |> find(css("[data-test=hero-primary-cta-#{index}]", visible: :any))
    |> Element.attr("href")
    |> URI.parse()
    |> Map.get(:path)
  end

  defp write_banner_image_fixture do
    path = Path.join(System.tmp_dir!(), @banner_image_fixture)

    # 1x1 transparent PNG.
    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
      )

    File.write!(path, png)
    path
  end

  # Wallaby's refute_has/2 checks once and fails while an element is still
  # leaving the DOM after a LiveView patch. Asserting a count of zero retries
  # until the element is gone (or the query times out).
  defp refute_has(parent, query), do: assert_has(parent, Wallaby.Query.count(query, 0))
end
