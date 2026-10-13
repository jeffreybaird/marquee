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

  # ---- Tags ---------------------------------------------------------------

  given_ "a tag with a given name already exists", fn world ->
    tag = insert(:tag, organization: world.org, name: "comedy")
    Map.put(world, :existing_tag, tag)
  end

  given_ "a tag exists", fn world ->
    tag = insert(:tag, organization: world.org, name: "drama")
    Map.put(world, :existing_tag, tag)
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
      |> visit_live("/admin/tags?org=#{world.org.slug}")
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
      |> visit_live("/admin/tags?org=#{world.org.slug}")
      |> accept_confirm(fn s ->
        click(s, css("[data-test=delete-tag-#{world.existing_tag.id}]"))
      end)
      |> refute_has(css("[data-test=delete-tag-#{world.existing_tag.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I type a search query in the tag search box", fn world ->
    session =
      world.session
      |> visit("/admin/tags?org=#{world.org.slug}")
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
    assert_text(world.session, "comedy")
    refute_has(world.session, Wallaby.Query.text("thriller"))
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
end
