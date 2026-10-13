defmodule MarqueeFeatures.Steps.ContentManagement do
  @moduledoc """
  Step definitions for content_management.feature.

  Focuses on Tags, Collections, and Series CRUD paths verified in the UI.
  Video upload (Mux-dependent) and advanced flows are scoped for later
  work; scenarios that touch them will show as undefined when `mix cucumber`
  runs.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser

  alias Marquee.Content
  alias Marquee.Content.Tag
  alias Marquee.Repo
  alias Marquee.Viewers.ViewerToken
  alias Wallaby.Element

  # ---- Tags ---------------------------------------------------------------

  given_ "a tag with a given name already exists", fn world ->
    tag = insert(:tag, organization: world.org, name: "comedy")
    Map.put(world, :existing_tag, tag)
  end

  given_ "a tag exists", fn world ->
    tag = insert(:tag, organization: world.org, name: "drama")

    # A tagged video lets the edit scenario check that the rename shows up
    # wherever the tag is applied, and the delete scenario check that the
    # association is dropped.
    video = ready_video(world.org, title: "Tagged Feature")
    insert(:video_tag, organization: world.org, video: video, tag: tag)

    Map.merge(world, %{existing_tag: tag, tagged_video: video})
  end

  given_ "multiple tags exist", fn world ->
    tags = [
      insert(:tag, organization: world.org, name: "comedy"),
      insert(:tag, organization: world.org, name: "drama"),
      insert(:tag, organization: world.org, name: "thriller")
    ]

    Map.put(world, :existing_tags, tags)
  end

  when_ "I create a tag with a valid name", fn world ->
    session =
      world.session
      |> visit("/admin/tags?org=#{world.org.slug}")
      |> fill_in(css("[data-test=new-tag-input]"), with: "comedy")
      |> click(css("[data-test=create-tag-btn]"))

    Map.merge(world, %{session: session, new_tag_name: "comedy"})
  end

  when_ "I try to create another tag with the same name", fn world ->
    session =
      world.session
      |> visit_settled("/admin/tags?org=#{world.org.slug}")
      |> fill_in(css("[data-test=new-tag-input]"), with: world.existing_tag.name)
      |> click(css("[data-test=create-tag-btn]"))

    Map.put(world, :session, session)
  end

  when_ "I delete it", fn world ->
    # Wallaby accepts the JS `confirm()` dialog triggered by `data-confirm`.
    # The row leaves the list once the LiveView has processed the delete;
    # wait for that before the next step reads the database.
    session =
      world.session
      |> visit_settled("/admin/tags?org=#{world.org.slug}")

    accept_confirm(session, fn s ->
      click(s, css("[data-test=delete-tag-#{world.existing_tag.id}]"))
    end)

    await_gone(session, css("[data-test=delete-tag-#{world.existing_tag.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I type a search query in the tag search box", fn world ->
    session =
      world.session
      |> visit_settled("/admin/tags?org=#{world.org.slug}")
      |> fill_in(css("[data-test=tag-search]"), with: "comedy")

    Map.put(world, :session, session)
  end

  then_ "the tag is created and available to assign to videos", fn world ->
    assert_text(world.session, world.new_tag_name)

    tag = Repo.get_by(Tag, organization_id: world.org.id, name: world.new_tag_name)
    assert tag, "expected tag #{world.new_tag_name} to exist in DB"

    world
  end

  then_ "I see a validation error", fn world ->
    assert_has(world.session, css("[role=alert]", text: "A tag with this name already exists."))
    world
  end

  then_ "no duplicate tag is created", fn world ->
    assert length(tags_named(world.org, world.existing_tag.name)) == 1,
           "expected exactly 1 tag named #{world.existing_tag.name}"

    world
  end

  then_ "the tag is removed from the system", fn world ->
    # Tags are user-facing content, so deletion is a soft delete: the row
    # keeps a `deleted_at` timestamp and drops out of the listing.
    assert {:ok, %Tag{deleted_at: %DateTime{}}} =
             Content.get_tag(world.org, world.existing_tag.id)

    %{results: tags} = Content.list_tags(world.org)

    refute Enum.any?(tags, &(&1.id == world.existing_tag.id)),
           "expected tag #{world.existing_tag.id} to be absent from the tag list"

    world
  end

  then_ "disassociated from all videos", fn world ->
    %{results: videos} = Content.list_videos_by_tag(world.org, world.existing_tag)
    assert videos == [], "expected no videos to remain tagged #{world.existing_tag.name}"
    world
  end

  then_ "the tag list filters to matching results", fn world ->
    tag_row = fn name ->
      tag = Enum.find(world.existing_tags, &(&1.name == name))
      css("[data-test=tag-#{tag.id}]")
    end

    # Wait for the filtered state: non-matching rows must leave the list
    # (retrying), and the matching row must still be present afterwards.
    world.session
    |> await_gone(tag_row.("thriller"))
    |> await_gone(tag_row.("drama"))
    |> assert_has(tag_row.("comedy"))

    world
  end

  defp tags_named(org, name) do
    %{results: tags} = Content.list_tags(org)
    Enum.filter(tags, &(&1.name == name))
  end

  # ---- Collections --------------------------------------------------------

  when_ "I create a collection with a name", fn world ->
    title = "Featured Shows #{System.unique_integer([:positive])}"

    session =
      world.session
      |> visit("/admin/collections?org=#{world.org.slug}")
      |> click(css("[data-test=new-collection-btn]"))
      |> fill_in(css("[data-test=collection-title-input]"), with: title)
      |> click(css("[data-test=save-collection-btn]"))

    Map.merge(world, %{session: session, new_collection_title: title})
  end

  then_ "the collection is saved and appears in the collections list", fn world ->
    # Sheet closes; collection appears on the index page.
    session = visit(world.session, "/admin/collections?org=#{world.org.slug}")
    assert_text(session, world.new_collection_title)
    Map.put(world, :session, session)
  end

  # ---- Series -------------------------------------------------------------

  when_ "I create a series with a name and metadata", fn world ->
    title = "Standup Specials #{System.unique_integer([:positive])}"

    session =
      world.session
      |> visit("/admin/series?org=#{world.org.slug}")
      |> click(css("[data-test=new-series-btn]"))
      |> fill_in(css("[data-test=series-title-input]"), with: title)
      |> click(css("[data-test=save-series-btn]"))

    Map.merge(world, %{session: session, new_series_title: title})
  end

  then_ "the series is saved and appears in the content library", fn world ->
    session = visit(world.session, "/admin/series?org=#{world.org.slug}")
    assert_text(session, world.new_series_title)
    Map.put(world, :session, session)
  end

  # ---- Tags: edit ---------------------------------------------------------

  when_ "I edit its name and save", fn world ->
    tag = world.existing_tag
    row = "[data-test=tag-#{tag.id}]"
    new_name = "melodrama"

    # The Edit/Save buttons and the inline input carry no data-test of
    # their own, so they are located inside the tag's data-test row.
    session =
      world.session
      |> visit_settled("/admin/tags?org=#{world.org.slug}")
      |> click(css("#{row} button", text: "Edit"))
      |> fill_in(css("#{row} input[name=name]"), with: new_name)
      |> click(css("#{row} button", text: "Save"))
      |> await_gone(css("#{row} input[name=name]"))

    Map.merge(world, %{session: session, edited_tag_name: new_name})
  end

  then_ "the tag name is updated", fn world ->
    tag = world.existing_tag

    assert_has(world.session, css("[data-test=tag-#{tag.id}]", text: world.edited_tag_name))
    assert {:ok, %Tag{name: name}} = Content.get_tag(world.org, tag.id)
    assert name == world.edited_tag_name

    world
  end

  then_ "all videos with that tag reflect the updated name", fn world ->
    tag = world.existing_tag
    video = world.tagged_video

    assert Enum.map(Content.list_video_tags(world.org, video), & &1.name) == [world.edited_tag_name]

    session =
      world.session
      |> visit_settled("/admin/content?org=#{world.org.slug}")
      |> assert_has(css("[data-test=row-tag-#{video.id}-#{tag.id}]", text: world.edited_tag_name))

    Map.put(world, :session, session)
  end

  # ---- Collections: setup ---------------------------------------------------

  given_ "a collection exists", fn world ->
    collection = insert(:collection, organization: world.org, title: "Weekend Picks")
    existing = ready_video(world.org, title: "Already Collected")
    insert(:collection_item, organization: world.org, collection: collection, video: existing, position: 0)

    candidates = [
      ready_video(world.org, title: "Fresh Arrival One"),
      ready_video(world.org, title: "Fresh Arrival Two")
    ]

    Map.merge(world, %{
      collection: collection,
      collection_existing_video: existing,
      candidate_videos: candidates
    })
  end

  given_ "a collection is hidden", fn world ->
    collection = insert(:collection, organization: world.org, title: "Backstage Vault", visible: false)
    video = ready_video(world.org, title: "Vault Exclusive")
    insert(:collection_item, organization: world.org, collection: collection, video: video, position: 0)
    Map.put(world, :collection, collection)
  end

  given_ "a collection and a series exist", fn world ->
    collection = insert(:collection, organization: world.org, title: "Binge List")
    %{series: series} = build_series(world.org, title: "Harbor Lights", seasons: ["Pilot Season"])
    Map.merge(world, %{collection: collection, series: series})
  end

  given_ "a collection has multiple items", fn world ->
    collection = insert(:collection, organization: world.org, title: "Ordered Picks")

    videos =
      for {title, position} <- Enum.with_index(["First Pick", "Second Pick", "Third Pick"]) do
        video = ready_video(world.org, title: title)

        insert(:collection_item,
          organization: world.org,
          collection: collection,
          video: video,
          position: position
        )

        video
      end

    Map.merge(world, %{collection: collection, collection_videos: videos})
  end

  given_ "a collection has items", fn world ->
    collection = insert(:collection, organization: world.org, title: "Trim Me")

    videos =
      for {title, position} <- Enum.with_index(["Keeper", "Goner"]) do
        video = ready_video(world.org, title: title)

        insert(:collection_item,
          organization: world.org,
          collection: collection,
          video: video,
          position: position
        )

        video
      end

    Map.merge(world, %{collection: collection, collection_videos: videos})
  end

  # ---- Collections: actions -------------------------------------------------

  when_ "I add videos to it", fn world ->
    [first, second] = world.candidate_videos

    session =
      world.session
      |> open_collection(world)
      |> click(css("[data-test=add-videos-btn]"))
      |> click(css("[data-test=picker-type-video]"))
      |> click(css("[data-test=select-video-#{first.id}]"))
      |> click(css("[data-test=select-video-#{second.id}]"))
      |> click(css("[data-test=add-selected-videos-btn]"))
      |> assert_has(css("[data-test=collection-video-#{first.id}]"))
      |> assert_has(css("[data-test=collection-video-#{second.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I add the series to the collection", fn world ->
    session =
      world.session
      |> open_collection(world)
      |> click(css("[data-test=add-videos-btn]"))
      |> click(css("[data-test=picker-type-series]"))
      |> click(css("[data-test=picker-item-series-#{world.series.id}]"))
      # Wait for the LiveView to render the added item before the outcome
      # step reads the database.
      |> assert_has(css("[data-test^=collection-item-] [data-test=type-badge]", text: "Series"))

    Map.put(world, :session, session)
  end

  when_ "I move an item up or down", fn world ->
    [first, second, third] = world.collection_videos

    # Move the last item up one slot: First, Third, Second.
    session =
      world.session
      |> open_collection(world)
      |> assert_has(css("[data-test=collection-video-#{third.id}]:nth-child(3)"))
      |> click(css("[data-test=collection-video-#{third.id}] button", text: "↑"))

    Map.merge(world, %{session: session, expected_item_order: [first, third, second]})
  end

  when_ "I remove an item", fn world ->
    [keeper, goner] = world.collection_videos

    session =
      world.session
      |> open_collection(world)
      |> assert_has(css("[data-test=collection-video-#{keeper.id}]"))

    accept_confirm(session, fn s ->
      click(s, css("[data-test=remove-video-#{goner.id}]"))
    end)

    await_gone(session, css("[data-test=collection-video-#{goner.id}]"))

    Map.merge(world, %{session: session, removed_video: goner, kept_video: keeper})
  end

  when_ "I delete the collection", fn world ->
    collection = world.collection

    session =
      world.session
      |> visit_settled("/admin/collections?org=#{world.org.slug}")
      |> assert_has(css("[data-test=collection-row-#{collection.id}]"))

    accept_confirm(session, fn s ->
      click(s, css("[data-test=delete-collection-#{collection.id}]"))
    end)

    await_gone(session, css("[data-test=collection-row-#{collection.id}]"))

    Map.merge(world, %{session: session, soft_deleted: {:collection, collection}})
  end

  # ---- Collections: outcomes ------------------------------------------------

  then_ "those videos appear as collection items in the correct order", fn world ->
    %{results: items} = Content.list_collection_items(world.org, world.collection)
    [existing_item | added_items] = items

    # The pre-existing item keeps its slot; the added videos follow it,
    # each at a later position than the one before.
    assert existing_item.video_id == world.collection_existing_video.id
    assert Enum.sort(Enum.map(added_items, & &1.video_id)) ==
             Enum.sort(Enum.map(world.candidate_videos, & &1.id))

    positions = Enum.map(items, & &1.position)
    assert positions == Enum.sort(positions) and positions == Enum.uniq(positions),
           "expected strictly increasing item positions, got #{inspect(positions)}"

    assert_ui_item_order(world.session, Enum.map(items, &"collection-video-#{&1.video_id}"))
    world
  end

  then_ "the series appears as a collection item", fn world ->
    %{results: items} = Content.list_collection_items(world.org, world.collection)
    item = Enum.find(items, &(&1.item_type == :series))

    assert item, "expected a series item in collection #{world.collection.id}"
    assert item.series_id == world.series.id

    session =
      world.session
      |> assert_has(css("[data-test=collection-item-#{item.id}]", text: world.series.title))
      |> assert_has(css("[data-test=collection-item-#{item.id}] [data-test=type-badge]", text: "Series"))

    Map.put(world, :session, session)
  end

  then_ "the display order is updated", fn world ->
    expected_ids = Enum.map(world.expected_item_order, & &1.id)

    # Wait for the re-render before reading the database.
    world.expected_item_order
    |> Enum.with_index(1)
    |> Enum.each(fn {video, n} ->
      assert_has(world.session, css("[data-test=collection-video-#{video.id}]:nth-child(#{n})"))
    end)

    %{results: items} = Content.list_collection_items(world.org, world.collection)
    assert Enum.map(items, & &1.video_id) == expected_ids
    world
  end

  then_ "it is no longer part of that collection", fn world ->
    %{results: items} = Content.list_collection_items(world.org, world.collection)
    video_ids = Enum.map(items, & &1.video_id)

    refute world.removed_video.id in video_ids
    assert world.kept_video.id in video_ids
    assert_has(world.session, css("[data-test=collection-video-#{world.kept_video.id}]"))
    world
  end

  then_ "viewers cannot see the collection on the platform", fn world ->
    assert {:ok, %{visible: false}} = Content.get_collection(world.org, world.collection.id)
    refute_viewer_sees_collection(world.org, world.collection)
    world
  end

  then_ "viewers can see the collection on the platform", fn world ->
    assert {:ok, %{visible: true}} = Content.get_collection(world.org, world.collection.id)

    with_viewer_session(fn session ->
      session
      |> visit_settled("/collections/#{world.collection.slug}?org=#{world.org.slug}")
      |> assert_has(css("[data-test=sv-collection-title]", text: world.collection.title))
    end)

    world
  end

  # ---- Soft delete (collections and series) ---------------------------------

  then_ "it is marked with a deleted_at timestamp", fn world ->
    case world.soft_deleted do
      {:collection, collection} ->
        assert {:ok, %{deleted_at: %DateTime{}}} = Content.get_collection(world.org, collection.id)

      {:series, series} ->
        assert {:ok, %{deleted_at: %DateTime{}}} = Content.get_series(world.org, series.id)
    end

    world
  end

  then_ "no longer appears to viewers", fn world ->
    case world.soft_deleted do
      {:collection, collection} ->
        %{results: collections} = Content.list_collections(world.org)
        refute Enum.any?(collections, &(&1.id == collection.id))
        refute_viewer_sees_collection(world.org, collection)

      {:series, series} ->
        %{results: series_list} = Content.list_series(world.org)
        refute Enum.any?(series_list, &(&1.id == series.id))
        refute_viewer_sees_series(world.org, series)
    end

    world
  end

  # ---- Series and seasons: setup --------------------------------------------

  given_ "a series exists", fn world ->
    %{series: series, seasons: [season]} =
      build_series(world.org, title: "Night Shift", seasons: ["Pilot Season"])

    Map.merge(world, %{series: series, season: season})
  end

  given_ "a season exists within a series", fn world ->
    %{series: series, seasons: [season]} =
      build_series(world.org, title: "Night Shift", seasons: ["Pilot Season"])

    Map.merge(world, %{series: series, season: season})
  end

  given_ "a season exists", fn world ->
    # Season 1 is the one the operator hides; season 2 stays visible so the
    # viewer's series page still has something to show.
    %{series: series, seasons: [season, other]} =
      build_series(world.org, title: "Night Shift", seasons: ["Pilot Season", "Second Wind"])

    Map.merge(world, %{series: series, season: season, other_season: other})
  end

  # ---- Series and seasons: actions ------------------------------------------

  when_ "I add a season with a name and season number", fn world ->
    session =
      world.session
      |> open_series(world.org, world.series)
      |> click(css("[data-test=new-season-btn]"))
      |> fill_in(css("[data-test=season-title-input]"), with: "Second Wind")
      |> fill_in(css("[data-test=season-number-input]"), with: "2")
      |> click(css("[data-test=save-season-btn]"))
      |> assert_has(css("[data-test=seasons-list]", text: "Second Wind"))

    Map.merge(world, %{session: session, new_season_title: "Second Wind", new_season_number: 2})
  end

  when_ "I edit the series name or metadata and save", fn world ->
    series = world.series
    new_title = "Night Shift Revisited"

    session =
      world.session
      |> visit_settled("/admin/series?org=#{world.org.slug}")
      |> click(css("[data-test=edit-series-#{series.id}]"))
      |> fill_in(css("[data-test=series-title-input]"), with: new_title)
      |> click(css("[data-test=save-series-btn]"))
      |> assert_has(css("[data-test=series-row-#{series.id}]", text: new_title))

    Map.merge(world, %{session: session, edited_series_title: new_title})
  end

  when_ "I edit the season details and save", fn world ->
    season = world.season
    new_title = "Pilot Season Remastered"

    session =
      world.session
      |> open_series(world.org, world.series)
      |> click(css("[data-test=edit-season-#{season.id}]"))
      |> fill_in(css("[data-test=season-title-input]"), with: new_title)
      |> fill_in(css("[data-test=season-number-input]"), with: "3")
      |> click(css("[data-test=save-season-btn]"))
      |> assert_has(css("[data-test=season-row-#{season.id}]", text: new_title))

    Map.merge(world, %{session: session, edited_season_title: new_title, edited_season_number: 3})
  end

  when_ "I delete the series", fn world ->
    series = world.series

    session =
      world.session
      |> visit_settled("/admin/series?org=#{world.org.slug}")
      |> assert_has(css("[data-test=series-row-#{series.id}]"))

    accept_confirm(session, fn s ->
      click(s, css("[data-test=delete-series-#{series.id}]"))
    end)

    await_gone(session, css("[data-test=series-row-#{series.id}]"))

    Map.merge(world, %{session: session, soft_deleted: {:series, series}})
  end

  # ---- Series and seasons: outcomes -----------------------------------------

  then_ "the season is created and linked to that series", fn world ->
    %{results: seasons} = Content.list_seasons(world.org, world.series)
    season = Enum.find(seasons, &(&1.title == world.new_season_title))

    assert season, "expected season #{world.new_season_title} under series #{world.series.id}"
    assert season.series_id == world.series.id
    assert season.season_number == world.new_season_number

    assert_has(world.session, css("[data-test=season-row-#{season.id}]", text: world.new_season_title))
    world
  end

  then_ "the series record is updated", fn world ->
    assert {:ok, series} = Content.get_series(world.org, world.series.id)
    assert series.title == world.edited_series_title
    world
  end

  then_ "the season record is updated", fn world ->
    assert {:ok, season} = Content.get_season(world.org, world.season.id)
    assert season.title == world.edited_season_title
    assert season.season_number == world.edited_season_number
    assert season.series_id == world.series.id
    world
  end

  then_ "viewers cannot see the series", fn world ->
    assert {:ok, %{visible: false}} = Content.get_series(world.org, world.series.id)
    refute_viewer_sees_series(world.org, world.series)
    world
  end

  then_ "viewers cannot see that season", fn world ->
    hidden = world.season
    assert {:ok, %{visible: false}} = Content.get_season(world.org, hidden.id)

    with_subscribed_viewer(world.org, fn session ->
      session
      |> visit_settled("/series/#{world.series.slug}/season/#{hidden.season_number}?org=#{world.org.slug}")
      # The series stays watchable through its visible season.
      |> assert_has(css("[data-test=watch-page]"))
      |> assert_has(css("[data-test=season-section-heading]", text: world.other_season.title))
      |> refute_has(css("[data-test=season-section-heading]", text: hidden.title))
      |> refute_has(css("[data-test=season-selector] option", text: hidden.title, visible: :any))
    end)

    world
  end

  # ---- Helpers ------------------------------------------------------------------

  defp ready_video(org, attrs) do
    insert(
      :video,
      Keyword.merge(
        [organization: org, mux_status: "ready", published: true, duration: 600.0],
        attrs
      )
    )
  end

  # A series whose seasons each hold one episode, so the viewer series
  # page (which skips seasons without episodes) can render every season.
  defp build_series(org, title: title, seasons: season_titles) do
    series = insert(:series, organization: org, title: title)

    seasons =
      for {season_title, number} <- Enum.with_index(season_titles, 1) do
        season =
          insert(:season,
            organization: org,
            series: series,
            title: season_title,
            season_number: number,
            episode_count: 1
          )

        video = ready_video(org, title: "#{season_title} Episode 1")
        insert(:episode, organization: org, season: season, video: video, episode_number: 1)
        season
      end

    %{series: series, seasons: seasons}
  end

  # The collection title is a button without its own data-test; it lives in
  # the collection's data-test row and opens the item view in place.
  defp open_collection(session, world) do
    collection = world.collection

    session
    |> visit_settled("/admin/collections?org=#{world.org.slug}")
    |> click(css("[data-test=collection-row-#{collection.id}] button", text: collection.title))
    |> assert_has(css("[data-test=add-videos-btn]"))
  end

  defp open_series(session, org, series) do
    session
    |> visit_settled("/admin/series?org=#{org.slug}")
    |> click(css("[data-test=view-series-#{series.id}]"))
    |> assert_has(css("[data-test=new-season-btn]"))
  end

  defp assert_ui_item_order(session, expected_test_ids) do
    expected_test_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {test_id, n} ->
      assert_has(session, css("[data-test=#{test_id}]:nth-child(#{n})"))
    end)

    actual =
      session
      |> all(css("[data-test^=collection-video-], [data-test^=collection-item-]"))
      |> Enum.map(&Element.attr(&1, "data-test"))

    assert actual == expected_test_ids
  end

  defp refute_viewer_sees_collection(org, collection) do
    with_viewer_session(fn session ->
      session
      |> visit_settled("/collections/#{collection.slug}?org=#{org.slug}")
      |> refute_has(css("[data-test=sv-collection-title]", text: collection.title))
      |> refute_has(css("[data-test=sv-collection-header]"))
    end)
  end

  defp refute_viewer_sees_series(org, series) do
    with_subscribed_viewer(org, fn session ->
      session
      |> visit_settled("/series/#{series.slug}?org=#{org.slug}")
      |> refute_has(css("[data-test=watch-page]"))
    end)
  end

  # Viewer checks run in their own browser so the operator's session and
  # cookies stay untouched.
  defp with_viewer_session(fun) do
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    try do
      fun.(session)
    after
      Wallaby.end_session(session)
    end
  end

  defp with_subscribed_viewer(org, fun) do
    with_viewer_session(fn session ->
      viewer = insert(:subscribed_viewer, organization: org)
      {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
      Repo.insert!(viewer_token)

      session
      |> visit("/magic-link/#{encoded_token}?org=#{org.slug}")
      |> assert_has(css("[data-test=viewer-sign-out]"))
      |> fun.()
    end)
  end

  # The suite runs Chrome with `pageLoadStrategy: "none"`, so `visit/2`
  # can return while the previous document is still current. Tag the old
  # document, wait for it to be replaced, then wait for the new page's
  # LiveView (the target page, or the viewer home after a redirect).
  defp visit_settled(session, path) do
    session
    |> execute_script("document.documentElement.setAttribute('data-cm-stale', ''); return true;")
    |> visit(path)
    |> refute_has(css("html[data-cm-stale]"))
    |> await_live_connect()
  end

  # The server can take longer than Wallaby's default wait to process a
  # mutation while the suite shares the machine with other browser runs.
  # Polls for up to 15s before failing with Wallaby's own refute message.
  defp await_gone(session, query, timeout_ms \\ 15_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_gone_until(session, query, deadline)
  end

  defp await_gone_until(session, query, deadline) do
    cond do
      not has?(session, query) -> session
      System.monotonic_time(:millisecond) >= deadline -> refute_has(session, query)
      true ->
        Process.sleep(250)
        await_gone_until(session, query, deadline)
    end
  end
end
