defmodule BobineFeatures.Steps.Content do
  @moduledoc """
  Video-related step definitions for content_management.feature.

  Edit + soft-delete now drive the admin UI via Wallaby. Restore still
  calls `Content.restore_video/2` directly because no operator-facing
  restore surface exists yet — flagged inline so the step can be
  promoted once that UI lands.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Bobine.Factory
  import ExUnit.Assertions

  alias Bobine.Content

  # ---- Setup --------------------------------------------------------------

  given_ "a video exists in the content library", fn world ->
    video = insert(:video, organization: world.org, mux_status: "ready")
    Map.put(world, :video, video)
  end

  given_ "a video has been soft-deleted", fn world ->
    video = insert(:video, organization: world.org, mux_status: "ready")
    {:ok, deleted} = Content.delete_video(world.scope, video)
    Map.merge(world, %{video: video, deleted_video: deleted})
  end

  # ---- Edit metadata (Wallaby) -------------------------------------------

  when_ "I edit the title or description and save", fn world ->
    session =
      world.session
      |> visit("/admin/content?org=#{world.org.slug}")
      |> click(css("[data-test=view-video-#{world.video.id}]"))
      |> click(css("[data-test=edit-video-btn]"))
      |> fill_in(css("[data-test=video-title-input]"), with: "Updated Title")
      |> fill_in(css("[data-test=video-description-input]"), with: "Updated description text")
      |> click(css("[data-test=save-video-btn]"))

    Map.put(world, :session, session)
  end

  then_ "the video record is updated with the new metadata", fn world ->
    assert_text(world.session, "Updated Title")
    assert_text(world.session, "Updated description text")

    # Secondary persistence check — the UI confirmation above is the
    # user-observable outcome; this guards against a stale page
    # rendering cached assigns.
    fetched = Content.get_video!(world.org, world.video.id)
    assert fetched.title == "Updated Title"
    assert fetched.description == "Updated description text"

    world
  end

  # ---- Soft-delete (Wallaby) ---------------------------------------------

  when_ "I delete the video", fn world ->
    session =
      world.session
      |> visit("/admin/content?org=#{world.org.slug}")
      |> accept_confirm(fn s ->
        click(s, css("[data-test=delete-video-#{world.video.id}]"))
      end)

    Map.put(world, :session, session)
  end

  then_ "the video is marked with a deleted_at timestamp", fn world ->
    # The DB check is primary here because deleted_at is an invisible
    # side effect — the user-observable result (the row disappearing
    # from the list) is covered by the following step.
    fetched = Content.get_video!(world.org, world.video.id)
    assert fetched.deleted_at != nil
    Map.put(world, :deleted_video, fetched)
  end

  then_ "it no longer appears in content listings", fn world ->
    session = visit(world.session, "/admin/content?org=#{world.org.slug}")
    refute_has(session, css("[data-test=view-video-#{world.video.id}]"))
    Map.put(world, :session, session)
  end

  # ---- Restore (legacy — context-direct) ---------------------------------
  # TODO: rewrite with Wallaby once an operator-facing restore surface
  # exists. There's no admin UI for it today, so asserting on a button
  # or link would silently pass against a non-existent element.

  then_ "it can be restored", fn world ->
    {:ok, restored} = Content.restore_video(world.scope, world.deleted_video)
    assert is_nil(restored.deleted_at)
    world
  end

  when_ "I restore the video", fn world ->
    {:ok, restored} = Content.restore_video(world.scope, world.deleted_video)
    Map.put(world, :restored_video, restored)
  end

  then_ "it reappears in the content library", fn world ->
    %{results: videos} = Content.list_videos(world.org)
    ids = Enum.map(videos, & &1.id)
    assert world.restored_video.id in ids
    world
  end
end
