defmodule BobineFeatures.Steps.Content do
  @moduledoc """
  Legacy video-related step definitions.

  These steps still exercise `Bobine.Content` directly instead of the admin
  UI. They remain temporarily so video scenarios don't go undefined overnight;
  rewrite each as Wallaby-driven UI assertions as the corresponding admin
  flow is verified (edit metadata, upload thumbnail, soft-delete, restore).

  Tag-related steps were moved to `content_management_steps.ex` and now
  drive the Tags admin page directly — do not restore the DB-direct
  equivalents here.
  """

  use Cucumberex.DSL

  import Bobine.Factory
  import ExUnit.Assertions

  alias Bobine.Content

  # ---- Video exists --------------------------------------------------------

  given_ "a video exists in the content library", fn world ->
    video = insert(:video, organization: world.org)
    Map.put(world, :video, video)
  end

  # ---- Edit metadata -------------------------------------------------------

  # TODO: rewrite with Wallaby — click video row, open edit form, submit.
  when_ "I edit the title or description and save", fn world ->
    {:ok, updated} =
      Content.update_video(world.scope, world.video, %{
        title: "Updated Title",
        description: "Updated description text"
      })

    Map.put(world, :updated_video, updated)
  end

  then_ "the video record is updated with the new metadata", fn world ->
    assert world.updated_video.title == "Updated Title"
    assert world.updated_video.description == "Updated description text"
    fetched = Content.get_video!(world.org, world.updated_video.id)
    assert fetched.title == "Updated Title"
    world
  end

  # ---- Soft delete ---------------------------------------------------------

  # TODO: rewrite with Wallaby — click delete icon on video row, confirm.
  when_ "I delete the video", fn world ->
    {:ok, deleted} = Content.delete_video(world.scope, world.video)
    Map.put(world, :deleted_video, deleted)
  end

  then_ "the video is marked with a deleted_at timestamp", fn world ->
    assert world.deleted_video.deleted_at != nil
    world
  end

  then_ "it no longer appears in content listings", fn world ->
    %{results: videos} = Content.list_videos(world.org)
    ids = Enum.map(videos, & &1.id)
    refute world.deleted_video.id in ids
    world
  end

  then_ "it can be restored", fn world ->
    {:ok, restored} = Content.restore_video(world.scope, world.deleted_video)
    assert is_nil(restored.deleted_at)
    %{results: videos} = Content.list_videos(world.org)
    ids = Enum.map(videos, & &1.id)
    assert restored.id in ids
    world
  end
end
