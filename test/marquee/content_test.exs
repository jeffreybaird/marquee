defmodule Marquee.ContentTest do
  use Marquee.DataCase

  alias Marquee.Accounts.Scope
  alias Marquee.Content
  alias Marquee.Content.MockMuxClient

  describe "videos" do
    alias Marquee.Content.Video

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

    test "list_videos/2 with tag_ids filters videos to those carrying any tag",
         %{org: org} do
      tag_a = insert(:tag, organization: org, name: "Action")
      tag_b = insert(:tag, organization: org, name: "Drama")
      tag_c = insert(:tag, organization: org, name: "Comedy")

      v_action = insert(:video, organization: org, title: "Action Pic")
      v_drama = insert(:video, organization: org, title: "Drama Pic")
      _v_comedy = insert(:video, organization: org, title: "Comedy Pic")
      _v_untagged = insert(:video, organization: org, title: "Untagged")

      insert(:video_tag, organization: org, video: v_action, tag: tag_a)
      insert(:video_tag, organization: org, video: v_drama, tag: tag_b)
      insert(:video_tag, organization: org, video: insert(:video, organization: org), tag: tag_c)

      %{results: results} = Content.list_videos(org, tag_ids: [tag_a.id, tag_b.id])

      ids = Enum.map(results, & &1.id) |> Enum.sort()
      assert ids == Enum.sort([v_action.id, v_drama.id])
    end

    test "list_videos/2 deduplicates videos that match multiple filter tags",
         %{org: org} do
      tag_a = insert(:tag, organization: org, name: "Action")
      tag_b = insert(:tag, organization: org, name: "Drama")
      video = insert(:video, organization: org, title: "Crossover")

      insert(:video_tag, organization: org, video: video, tag: tag_a)
      insert(:video_tag, organization: org, video: video, tag: tag_b)

      %{results: results} = Content.list_videos(org, tag_ids: [tag_a.id, tag_b.id])

      assert [%{id: id}] = results
      assert id == video.id
    end

    test "list_videos/2 with empty tag_ids list returns unfiltered list",
         %{org: org} do
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)

      %{results: results} = Content.list_videos(org, tag_ids: [])

      ids = Enum.map(results, & &1.id) |> Enum.sort()
      assert ids == Enum.sort([v1.id, v2.id])
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

    test "get_video!/2 returns the video with given id", %{org: org} do
      video = insert(:video, organization: org)
      found = Content.get_video!(org, video.id)
      assert found.id == video.id
      assert found.title == video.title
    end

    test "get_video!/2 raises for another org's video", %{org: org} do
      other_org = insert(:organization)
      video = insert(:video, organization: other_org)

      assert_raise Ecto.NoResultsError, fn ->
        Content.get_video!(org, video.id)
      end
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

      assert Content.get_video!(org, video.id).title == video.title
    end

    test "delete_video/1 soft-deletes the video", %{org: org} do
      video = insert(:video, organization: org)
      assert {:ok, %Video{} = deleted} = Content.delete_video(video)
      assert deleted.deleted_at != nil
      assert Content.get_video!(org, video.id).deleted_at != nil
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

    test "list_videos_including_deleted/1 returns soft-deleted videos", %{org: org} do
      video = insert(:video, organization: org)
      {:ok, _deleted} = Content.delete_video(video)
      assert [found] = Content.list_videos_including_deleted(org)
      assert found.id == video.id
      assert found.deleted_at != nil
    end

    test "list_videos_including_deleted/1 scopes to org", %{org: org} do
      other_org = insert(:organization)
      _foreign = insert(:video, organization: other_org)
      mine = insert(:video, organization: org)

      results = Content.list_videos_including_deleted(org)
      assert Enum.map(results, & &1.id) == [mine.id]
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
      _video = insert(:video, mux_upload_id: "upload_xyz", mux_status: "waiting")

      assert {:ok, updated} = Content.link_upload_to_asset("upload_xyz", "asset_abc")
      assert updated.mux_asset_id == "asset_abc"
      assert updated.mux_status == "preparing"
    end

    test "link_upload_to_asset/2 returns not_found for unknown upload" do
      assert {:error, :not_found} = Content.link_upload_to_asset("unknown", "asset_abc")
    end

    test "mark_video_ready/2 sets video to ready with metadata" do
      _video = insert(:video, mux_asset_id: "asset_123", mux_status: "preparing")

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
      _video = insert(:video, mux_asset_id: "asset_456", mux_status: "preparing")

      assert {:ok, updated} = Content.mark_video_errored("asset_456", %{message: "encode failed"})
      assert updated.mux_status == "errored"
    end
  end

  describe "create_upload_url/2" do
    import Mox

    setup do
      verify_on_exit!()

      # Simulate dev-like CORS config (the bug was that this was missing,
      # causing production domain to be used in dev)
      Application.put_env(:marquee, :cors_origin, "http://localhost:4000")

      on_exit(fn ->
        Application.delete_env(:marquee, :cors_origin)
      end)

      :ok
    end

    test "creates a video in waiting status and returns an upload URL" do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)

      expect(MockMuxClient, :create_direct_upload, fn params ->
        # Must use the configured :cors_origin, not the production domain
        assert params.cors_origin == "http://localhost:4000"
        assert params.new_asset_settings.playback_policy == ["public"]
        assert params.new_asset_settings.video_quality == "plus"

        {:ok, %{"id" => "upload_abc", "url" => "https://storage.mux.com/upload_abc"}}
      end)

      assert {:ok, %{video: video, upload_url: url}} =
               Content.create_upload_url(scope, %{title: "Test Upload"})

      assert video.mux_status == "waiting"
      assert video.mux_upload_id == "upload_abc"
      assert video.organization_id == org.id
      assert video.title == "Test Upload"
      assert video.slug == "test-upload"
      assert url == "https://storage.mux.com/upload_abc"

      # Video must be visible in list immediately after creation
      assert %{results: [found]} = Content.list_videos(org)
      assert found.id == video.id
      assert found.mux_status == "waiting"
    end

    test "uses configured cors_origin over production domain" do
      # This test verifies the fix for the CORS bug where dev uploads
      # failed because the origin was set to https://slug.marquee.dev
      # instead of http://localhost:4000
      org = insert(:organization, slug: "my-studio", custom_domain: nil)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)

      expect(MockMuxClient, :create_direct_upload, fn params ->
        # Should use the configured :cors_origin, NOT "https://my-studio.marquee.dev"
        assert params.cors_origin == "http://localhost:4000"
        refute params.cors_origin =~ "marquee.dev"
        {:ok, %{"id" => "upload_xyz", "url" => "https://storage.mux.com/xyz"}}
      end)

      assert {:ok, _} = Content.create_upload_url(scope, %{title: "CORS Test"})
    end

    test "falls back to production domain when cors_origin is not configured" do
      Application.delete_env(:marquee, :cors_origin)

      org = insert(:organization, slug: "my-studio", custom_domain: nil)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)

      expect(MockMuxClient, :create_direct_upload, fn params ->
        assert params.cors_origin == "https://my-studio.marquee.dev"
        {:ok, %{"id" => "upload_prod", "url" => "https://storage.mux.com/prod"}}
      end)

      assert {:ok, _} = Content.create_upload_url(scope, %{title: "Prod CORS Test"})
    end

    test "uses current request origin when cors_origin is wildcard" do
      Application.put_env(:marquee, :cors_origin, "*")

      org = insert(:organization, slug: "my-studio", custom_domain: nil)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)

      expect(MockMuxClient, :create_direct_upload, fn params ->
        assert params.cors_origin == "http://demo.localhost:4000"
        {:ok, %{"id" => "upload_demo", "url" => "https://storage.mux.com/demo"}}
      end)

      assert {:ok, _} =
               Content.create_upload_url(scope, %{title: "Wildcard CORS Test"},
                 current_origin: "http://demo.localhost:4000"
               )
    end

    test "uses localhost fallback when cors_origin is wildcard and current origin is missing" do
      Application.put_env(:marquee, :cors_origin, "*")

      org = insert(:organization, slug: "my-studio", custom_domain: nil)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)

      expect(MockMuxClient, :create_direct_upload, fn params ->
        assert params.cors_origin == "http://localhost:4000"
        {:ok, %{"id" => "upload_local", "url" => "https://storage.mux.com/local"}}
      end)

      assert {:ok, _} = Content.create_upload_url(scope, %{title: "Wildcard Local Fallback"})
    end

    test "returns mux_error when Mux API fails" do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)

      expect(MockMuxClient, :create_direct_upload, fn _params ->
        {:error, :mux_error, "service unavailable"}
      end)

      assert {:error, :mux_error, _} = Content.create_upload_url(scope, %{title: "Fail Test"})

      # No video record should be created when Mux fails
      assert %{results: []} = Content.list_videos(org)
    end

    test "uses configured mux_video_quality" do
      Application.put_env(:marquee, :mux_video_quality, "basic")

      on_exit(fn ->
        Application.delete_env(:marquee, :mux_video_quality)
      end)

      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      scope =
        Scope.for_user(user)
        |> Scope.with_organization(org, membership)

      expect(MockMuxClient, :create_direct_upload, fn params ->
        assert params.new_asset_settings.video_quality == "basic"
        {:ok, %{"id" => "upload_basic", "url" => "https://storage.mux.com/basic"}}
      end)

      assert {:ok, %{upload_url: "https://storage.mux.com/basic"}} =
               Content.create_upload_url(scope, %{title: "Basic Quality Test"})
    end
  end

  describe "collections" do
    alias Marquee.Content.Collection
    alias Scope

    setup do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      %{org: org, scope: scope}
    end

    test "list_collections/2 returns all collections for the org", %{org: org, scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "Test", position: 0})
      assert %{results: [found]} = Content.list_collections(org)
      assert found.id == collection.id
    end

    test "get_collection/2 returns the collection in the org", %{org: org, scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "Test", position: 0})
      assert {:ok, found} = Content.get_collection(org, collection.id)
      assert found.id == collection.id
    end

    test "get_collection!/2 returns the collection in the org", %{org: org, scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "Test", position: 0})
      found = Content.get_collection!(org, collection.id)
      assert found.id == collection.id
    end

    test "create_collection/2 with valid data creates a collection", %{scope: scope} do
      valid_attrs = %{
        position: 42,
        description: "some description",
        title: "some title"
      }

      assert {:ok, %Collection{} = collection} = Content.create_collection(scope, valid_attrs)
      assert collection.position == 42
      assert collection.title == "some title"
    end

    test "create_collection/2 generates slug from title", %{scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "My Collection"})
      assert collection.slug == "my-collection"
    end

    test "create_collection/2 with invalid data returns error changeset", %{scope: scope} do
      assert {:error, :validation, %Ecto.Changeset{}} =
               Content.create_collection(scope, %{title: nil})
    end

    test "update_collection/3 with valid data updates the collection", %{scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "Original", position: 0})

      update_attrs = %{
        position: 43,
        description: "some updated description",
        title: "some updated title"
      }

      assert {:ok, %Collection{} = updated} =
               Content.update_collection(scope, collection, update_attrs)

      assert updated.position == 43
      assert updated.title == "some updated title"
    end

    test "update_collection/3 with invalid data returns error changeset", %{scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "Original", position: 0})

      assert {:error, :validation, %Ecto.Changeset{}} =
               Content.update_collection(scope, collection, %{title: nil})
    end

    test "delete_collection/2 soft-deletes the collection", %{org: org, scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "To Delete", position: 0})
      assert {:ok, %Collection{} = deleted} = Content.delete_collection(scope, collection)
      assert deleted.deleted_at != nil
      assert %{results: []} = Content.list_collections(org)
    end

    test "restore_collection/2 restores a soft-deleted collection", %{scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "To Restore", position: 0})
      {:ok, deleted} = Content.delete_collection(scope, collection)
      assert {:ok, %Collection{} = restored} = Content.restore_collection(scope, deleted)
      assert restored.deleted_at == nil
    end

    test "list_collections_including_deleted/1 returns soft-deleted collections", %{
      org: org,
      scope: scope
    } do
      {:ok, collection} = Content.create_collection(scope, %{title: "Deletable", position: 0})
      {:ok, _deleted} = Content.delete_collection(scope, collection)
      assert [found] = Content.list_collections_including_deleted(org)
      assert found.id == collection.id
      assert found.deleted_at != nil
    end

    test "change_collection/1 returns a collection changeset" do
      collection = %Collection{}
      assert %Ecto.Changeset{} = Content.change_collection(collection)
    end
  end

  describe "reconcile_pending_mux_assets/1" do
    import Mox

    alias Marquee.Content.Video

    setup do
      verify_on_exit!()
      org = insert(:organization)
      %{org: org}
    end

    test "flips a ready Mux asset to ready with playback metadata", %{org: org} do
      video =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_ready_1",
          mux_status: "preparing",
          mux_playback_id: nil
        )

      expect(MockMuxClient, :get_asset, fn "asset_ready_1" ->
        {:ok,
         %{
           "status" => "ready",
           "duration" => 42.0,
           "max_stored_resolution" => "1080p",
           "playback_ids" => [
             %{"id" => "pb_public_1", "policy" => "public"},
             %{"id" => "pb_signed_1", "policy" => "signed"}
           ]
         }}
      end)

      assert %{ready: 1, errored: 0, still_pending: 0, failed: 0} =
               Content.reconcile_pending_mux_assets()

      reloaded = Repo.get!(Video, video.id)
      assert reloaded.mux_status == "ready"
      assert reloaded.mux_playback_id == "pb_public_1"
      assert reloaded.duration == 42.0
    end

    test "marks an errored Mux asset as errored", %{org: org} do
      video =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_err_1",
          mux_status: "preparing"
        )

      expect(MockMuxClient, :get_asset, fn "asset_err_1" ->
        {:ok, %{"status" => "errored", "errors" => %{"messages" => ["bad input"]}}}
      end)

      assert %{ready: 0, errored: 1, still_pending: 0, failed: 0} =
               Content.reconcile_pending_mux_assets()

      assert Repo.get!(Video, video.id).mux_status == "errored"
    end

    test "leaves a still-preparing asset pending", %{org: org} do
      video =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_prep_1",
          mux_status: "preparing"
        )

      expect(MockMuxClient, :get_asset, fn "asset_prep_1" ->
        {:ok, %{"status" => "preparing"}}
      end)

      assert %{ready: 0, errored: 0, still_pending: 1, failed: 0} =
               Content.reconcile_pending_mux_assets()

      assert Repo.get!(Video, video.id).mux_status == "preparing"
    end

    test "counts a Mux API error as failed without changing the video", %{org: org} do
      video =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_fail_1",
          mux_status: "preparing"
        )

      expect(MockMuxClient, :get_asset, fn "asset_fail_1" ->
        {:error, :mux_error, %{type: :timeout, messages: ["boom"]}}
      end)

      assert %{ready: 0, errored: 0, still_pending: 0, failed: 1} =
               Content.reconcile_pending_mux_assets()

      assert Repo.get!(Video, video.id).mux_status == "preparing"
    end

    test "counts a raising Mux SDK call as failed and keeps going", %{org: org} do
      # The Mux SDK raises (e.g. Mux.Exception on a 404) rather than returning
      # an error tuple. A single raising asset must not abort the whole batch.
      raising =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_raise_1",
          mux_status: "preparing"
        )

      ready =
        insert(:video,
          organization: org,
          mux_asset_id: "asset_ready_2",
          mux_status: "preparing",
          mux_playback_id: nil
        )

      expect(MockMuxClient, :get_asset, 2, fn
        "asset_raise_1" -> raise "boom from Mux SDK"
        "asset_ready_2" -> {:ok, %{"status" => "ready", "playback_ids" => []}}
      end)

      assert %{ready: 1, errored: 0, still_pending: 0, failed: 1} =
               Content.reconcile_pending_mux_assets()

      assert Repo.get!(Video, raising.id).mux_status == "preparing"
      assert Repo.get!(Video, ready.id).mux_status == "ready"
    end

    test "ignores videos that are already ready or lack an asset id", %{org: org} do
      insert(:video, organization: org, mux_status: "ready")
      insert(:video, organization: org, mux_status: "waiting", mux_asset_id: nil)

      # No get_asset expectation set — a call would fail verify_on_exit!.
      assert %{ready: 0, errored: 0, still_pending: 0, failed: 0} =
               Content.reconcile_pending_mux_assets()
    end
  end

  describe "total_ready_duration/1" do
    setup do
      %{org: insert(:organization)}
    end

    test "sums ready, non-deleted, non-sample video durations", %{org: org} do
      insert(:video, organization: org, mux_status: "ready", duration: 100.0)
      insert(:video, organization: org, mux_status: "ready", duration: 50.5)

      assert Content.total_ready_duration(org) == 150.5
    end

    test "excludes sample content from the total", %{org: org} do
      insert(:video, organization: org, mux_status: "ready", duration: 100.0)
      insert(:video, organization: org, mux_status: "ready", duration: 9000.0, is_sample: true)

      assert Content.total_ready_duration(org) == 100.0
    end

    test "excludes non-ready and soft-deleted videos", %{org: org} do
      insert(:video, organization: org, mux_status: "ready", duration: 100.0)
      insert(:video, organization: org, mux_status: "preparing", duration: 500.0)

      insert(:video,
        organization: org,
        mux_status: "ready",
        duration: 500.0,
        deleted_at: ~U[2026-01-01 00:00:00Z]
      )

      assert Content.total_ready_duration(org) == 100.0
    end

    test "returns 0.0 when the org has no counted videos", %{org: org} do
      insert(:video, organization: org, mux_status: "ready", duration: 42.0, is_sample: true)

      assert Content.total_ready_duration(org) == 0.0
    end
  end
end
