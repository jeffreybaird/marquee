defmodule Bobine.ContentTest do
  use Bobine.DataCase

  alias Bobine.Content

  describe "videos" do
    alias Bobine.Content.Video

    @invalid_attrs %{
      description: nil,
      title: nil,
      slug: nil,
      mux_asset_id: nil,
      mux_playback_id: nil,
      mux_upload_id: nil,
      mux_status: nil,
      duration: nil,
      max_resolution: nil,
      published: nil
    }

    setup do
      org = insert(:organization)
      %{org: org}
    end

    defp create_video(%{org: org}) do
      video = insert(:video, organization: org)
      %{video: video}
    end

    test "list_videos/2 returns all videos for the org", %{org: org} do
      video = insert(:video, organization: org)
      assert %{results: [found]} = Content.list_videos(org)
      assert found.id == video.id
    end

    test "list_videos/2 excludes videos from other orgs", %{org: org} do
      other_org = insert(:organization)
      insert(:video, organization: org)
      insert(:video, organization: other_org)
      assert %{results: [_one]} = Content.list_videos(org)
    end

    test "get_video/2 returns the video in the org", %{org: org} do
      video = insert(:video, organization: org)
      assert {:ok, found} = Content.get_video(org, video.id)
      assert found.id == video.id
    end

    test "get_video/2 returns not_found for other org video", %{org: org} do
      other_org = insert(:organization)
      video = insert(:video, organization: other_org)
      assert {:error, :not_found} = Content.get_video(org, video.id)
    end

    test "get_video!/1 returns the video with given id", %{org: org} do
      video = insert(:video, organization: org)
      found = Content.get_video!(video.id)
      assert found.id == video.id
      assert found.title == video.title
    end

    test "create_video/1 with valid data creates a video", %{org: org} do
      valid_attrs = %{
        description: "some description",
        title: "some title",
        slug: "some-slug",
        mux_asset_id: "some mux_asset_id",
        mux_playback_id: "some mux_playback_id",
        mux_upload_id: "some mux_upload_id",
        mux_status: "ready",
        duration: 120.5,
        max_resolution: "some max_resolution",
        published: true,
        organization_id: org.id
      }

      assert {:ok, %Video{} = video} = Content.create_video(valid_attrs)
      assert video.description == "some description"
      assert video.title == "some title"
      assert video.slug == "some-slug"
    end

    test "create_video/1 with invalid data returns error changeset" do
      assert {:error, :validation, %Ecto.Changeset{}} = Content.create_video(@invalid_attrs)
    end

    test "update_video/2 with valid data updates the video", %{org: org} do
      video = insert(:video, organization: org)

      update_attrs = %{
        description: "some updated description",
        title: "some updated title",
        slug: "some-updated-slug"
      }

      assert {:ok, %Video{} = video} = Content.update_video(video, update_attrs)
      assert video.description == "some updated description"
      assert video.title == "some updated title"
    end

    test "update_video/2 with invalid data returns error changeset", %{org: org} do
      video = insert(:video, organization: org)

      assert {:error, :validation, %Ecto.Changeset{}} =
               Content.update_video(video, @invalid_attrs)

      assert Content.get_video!(video.id).title == video.title
    end

    test "delete_video/1 soft-deletes the video", %{org: org} do
      video = insert(:video, organization: org)
      assert {:ok, %Video{} = deleted} = Content.delete_video(video)
      assert deleted.deleted_at != nil
      assert Content.get_video!(video.id).deleted_at != nil
      assert %{results: []} = Content.list_videos(org)
    end

    test "restore_video/1 restores a soft-deleted video", %{org: org} do
      video = insert(:video, organization: org)
      {:ok, deleted} = Content.delete_video(video)
      assert {:ok, %Video{} = restored} = Content.restore_video(deleted)
      assert restored.deleted_at == nil
      assert %{results: [found]} = Content.list_videos(org)
      assert found.id == restored.id
    end

    test "list_videos_including_deleted/0 returns soft-deleted videos", %{org: org} do
      video = insert(:video, organization: org)
      {:ok, _deleted} = Content.delete_video(video)
      assert [found] = Content.list_videos_including_deleted()
      assert found.id == video.id
      assert found.deleted_at != nil
    end

    test "change_video/1 returns a video changeset", %{org: org} do
      video = insert(:video, organization: org)
      assert %Ecto.Changeset{} = Content.change_video(video)
    end
  end

  describe "slugify/1" do
    test "converts title to slug" do
      assert Content.slugify("My Awesome Video!") == "my-awesome-video"
    end

    test "handles multiple spaces and dashes" do
      assert Content.slugify("  Spaces  and---dashes  ") == "spaces-and-dashes"
    end

    test "handles empty string" do
      slug = Content.slugify("")
      assert String.starts_with?(slug, "untitled-")
    end
  end

  describe "webhook handlers" do
    test "link_upload_to_asset/2 links upload to asset" do
      video = insert(:video, mux_upload_id: "upload_xyz", mux_status: "waiting")

      assert {:ok, updated} = Content.link_upload_to_asset("upload_xyz", "asset_abc")
      assert updated.mux_asset_id == "asset_abc"
      assert updated.mux_status == "preparing"
    end

    test "link_upload_to_asset/2 returns not_found for unknown upload" do
      assert {:error, :not_found} = Content.link_upload_to_asset("unknown", "asset_abc")
    end

    test "mark_video_ready/2 sets video to ready with metadata" do
      video = insert(:video, mux_asset_id: "asset_123", mux_status: "preparing")

      metadata = %{
        duration: 125.5,
        max_resolution: "1080p",
        playback_id: "playback_abc"
      }

      assert {:ok, updated} = Content.mark_video_ready("asset_123", metadata)
      assert updated.mux_status == "ready"
      assert updated.duration == 125.5
      assert updated.max_resolution == "1080p"
      assert updated.mux_playback_id == "playback_abc"
    end

    test "mark_video_errored/2 sets video to errored" do
      video = insert(:video, mux_asset_id: "asset_456", mux_status: "preparing")

      assert {:ok, updated} = Content.mark_video_errored("asset_456", %{message: "encode failed"})
      assert updated.mux_status == "errored"
    end
  end

  describe "collections" do
    alias Bobine.Content.Collection

    import Bobine.ContentFixtures

    @invalid_attrs %{position: nil, type: nil, description: nil, title: nil, slug: nil}

    setup do
      %{org: insert(:organization)}
    end

    test "list_collections/0 returns all collections" do
      collection = collection_fixture()
      assert %{results: [^collection]} = Content.list_collections()
    end

    test "get_collection!/1 returns the collection with given id" do
      collection = collection_fixture()
      assert Content.get_collection!(collection.id) == collection
    end

    test "create_collection/1 with valid data creates a collection", %{org: org} do
      valid_attrs = %{
        position: 42,
        type: :series,
        description: "some description",
        title: "some title",
        slug: "some slug",
        organization_id: org.id
      }

      assert {:ok, %Collection{} = collection} = Content.create_collection(valid_attrs)
      assert collection.position == 42
      assert collection.type == :series
    end

    test "create_collection/1 with invalid data returns error changeset" do
      assert {:error, :validation, %Ecto.Changeset{}} = Content.create_collection(@invalid_attrs)
    end

    test "update_collection/2 with valid data updates the collection" do
      collection = collection_fixture()

      update_attrs = %{
        position: 43,
        type: :season,
        description: "some updated description",
        title: "some updated title",
        slug: "some updated slug"
      }

      assert {:ok, %Collection{} = collection} =
               Content.update_collection(collection, update_attrs)

      assert collection.position == 43
      assert collection.type == :season
    end

    test "update_collection/2 with invalid data returns error changeset" do
      collection = collection_fixture()

      assert {:error, :validation, %Ecto.Changeset{}} =
               Content.update_collection(collection, @invalid_attrs)

      assert collection == Content.get_collection!(collection.id)
    end

    test "delete_collection/1 soft-deletes the collection" do
      collection = collection_fixture()
      assert {:ok, %Collection{} = deleted} = Content.delete_collection(collection)
      assert deleted.deleted_at != nil
      assert %{results: []} = Content.list_collections()
    end

    test "restore_collection/1 restores a soft-deleted collection" do
      collection = collection_fixture()
      {:ok, deleted} = Content.delete_collection(collection)
      assert {:ok, %Collection{} = restored} = Content.restore_collection(deleted)
      assert restored.deleted_at == nil
    end

    test "list_collections_including_deleted/0 returns soft-deleted collections" do
      collection = collection_fixture()
      {:ok, _deleted} = Content.delete_collection(collection)
      assert [found] = Content.list_collections_including_deleted()
      assert found.id == collection.id
      assert found.deleted_at != nil
    end

    test "change_collection/1 returns a collection changeset" do
      collection = collection_fixture()
      assert %Ecto.Changeset{} = Content.change_collection(collection)
    end
  end
end
