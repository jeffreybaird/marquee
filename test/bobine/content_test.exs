defmodule Bobine.ContentTest do
  use Bobine.DataCase

  alias Bobine.Content

  describe "videos" do
    alias Bobine.Content.Video

    import Bobine.ContentFixtures

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
      %{org: insert(:organization)}
    end

    test "list_videos/0 returns all videos" do
      video = video_fixture()
      assert Content.list_videos() == [video]
    end

    test "get_video!/1 returns the video with given id" do
      video = video_fixture()
      assert Content.get_video!(video.id) == video
    end

    test "create_video/1 with valid data creates a video", %{org: org} do
      valid_attrs = %{
        description: "some description",
        title: "some title",
        slug: "some slug",
        mux_asset_id: "some mux_asset_id",
        mux_playback_id: "some mux_playback_id",
        mux_upload_id: "some mux_upload_id",
        mux_status: "some mux_status",
        duration: 120.5,
        max_resolution: "some max_resolution",
        published: true,
        organization_id: org.id
      }

      assert {:ok, %Video{} = video} = Content.create_video(valid_attrs)
      assert video.description == "some description"
      assert video.title == "some title"
      assert video.slug == "some slug"
      assert video.mux_asset_id == "some mux_asset_id"
      assert video.mux_playback_id == "some mux_playback_id"
      assert video.mux_upload_id == "some mux_upload_id"
      assert video.mux_status == "some mux_status"
      assert video.duration == 120.5
      assert video.max_resolution == "some max_resolution"
      assert video.published == true
    end

    test "create_video/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Content.create_video(@invalid_attrs)
    end

    test "update_video/2 with valid data updates the video" do
      video = video_fixture()

      update_attrs = %{
        description: "some updated description",
        title: "some updated title",
        slug: "some updated slug",
        mux_asset_id: "some updated mux_asset_id",
        mux_playback_id: "some updated mux_playback_id",
        mux_upload_id: "some updated mux_upload_id",
        mux_status: "some updated mux_status",
        duration: 456.7,
        max_resolution: "some updated max_resolution",
        published: false
      }

      assert {:ok, %Video{} = video} = Content.update_video(video, update_attrs)
      assert video.description == "some updated description"
      assert video.title == "some updated title"
      assert video.slug == "some updated slug"
      assert video.mux_asset_id == "some updated mux_asset_id"
      assert video.mux_playback_id == "some updated mux_playback_id"
      assert video.mux_upload_id == "some updated mux_upload_id"
      assert video.mux_status == "some updated mux_status"
      assert video.duration == 456.7
      assert video.max_resolution == "some updated max_resolution"
      assert video.published == false
    end

    test "update_video/2 with invalid data returns error changeset" do
      video = video_fixture()
      assert {:error, %Ecto.Changeset{}} = Content.update_video(video, @invalid_attrs)
      assert video == Content.get_video!(video.id)
    end

    test "delete_video/1 deletes the video" do
      video = video_fixture()
      assert {:ok, %Video{}} = Content.delete_video(video)
      assert_raise Ecto.NoResultsError, fn -> Content.get_video!(video.id) end
    end

    test "change_video/1 returns a video changeset" do
      video = video_fixture()
      assert %Ecto.Changeset{} = Content.change_video(video)
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
      assert Content.list_collections() == [collection]
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
      assert collection.description == "some description"
      assert collection.title == "some title"
      assert collection.slug == "some slug"
    end

    test "create_collection/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Content.create_collection(@invalid_attrs)
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
      assert collection.description == "some updated description"
      assert collection.title == "some updated title"
      assert collection.slug == "some updated slug"
    end

    test "update_collection/2 with invalid data returns error changeset" do
      collection = collection_fixture()
      assert {:error, %Ecto.Changeset{}} = Content.update_collection(collection, @invalid_attrs)
      assert collection == Content.get_collection!(collection.id)
    end

    test "delete_collection/1 deletes the collection" do
      collection = collection_fixture()
      assert {:ok, %Collection{}} = Content.delete_collection(collection)
      assert_raise Ecto.NoResultsError, fn -> Content.get_collection!(collection.id) end
    end

    test "change_collection/1 returns a collection changeset" do
      collection = collection_fixture()
      assert %Ecto.Changeset{} = Content.change_collection(collection)
    end
  end
end
