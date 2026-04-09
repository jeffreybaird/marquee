defmodule Bobine.Catalog.CatalogTest do
  use Bobine.DataCase

  alias Bobine.Accounts.Scope
  alias Bobine.Catalog
  alias Bobine.Content

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{org: org, scope: scope}
  end

  describe "list_rows/2" do
    test "returns rows in position order", %{org: org, scope: scope} do
      {:ok, r2} =
        Catalog.create_row(scope, %{
          title: "Second",
          source_type: :curated,
          position: 1,
          max_items: 20
        })

      {:ok, r1} =
        Catalog.create_row(scope, %{
          title: "First",
          source_type: :curated,
          position: 0,
          max_items: 20
        })

      %{results: rows} = Catalog.list_rows(org)
      ids = Enum.map(rows, & &1.id)
      assert ids == [r1.id, r2.id]
    end
  end

  describe "list_visible_rows/2" do
    test "returns only visible, non-deleted rows in position order", %{org: org, scope: scope} do
      {:ok, _hidden} =
        Catalog.create_row(scope, %{
          title: "Hidden",
          source_type: :curated,
          visible: false,
          position: 0,
          max_items: 20
        })

      {:ok, visible2} =
        Catalog.create_row(scope, %{
          title: "Visible Second",
          source_type: :curated,
          visible: true,
          position: 2,
          max_items: 20
        })

      {:ok, visible1} =
        Catalog.create_row(scope, %{
          title: "Visible First",
          source_type: :curated,
          visible: true,
          position: 1,
          max_items: 20
        })

      %{results: rows} = Catalog.list_visible_rows(org)
      ids = Enum.map(rows, & &1.id)
      assert ids == [visible1.id, visible2.id]
    end

    test "excludes soft-deleted rows", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Will Delete",
          source_type: :curated,
          visible: true,
          position: 0,
          max_items: 20
        })

      Catalog.delete_row(scope, row)

      %{results: rows} = Catalog.list_visible_rows(org)
      assert rows == []
    end
  end

  describe "create_row/2" do
    test "with curated source type succeeds", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{title: "Curated", source_type: :curated, max_items: 20})

      assert row.source_type == :curated
    end

    test "with max_items below 5 returns validation error", %{scope: scope} do
      assert {:error, :validation, changeset} =
               Catalog.create_row(scope, %{title: "Bad", source_type: :curated, max_items: 4})

      assert errors_on(changeset)[:max_items] != nil
    end

    test "with max_items above 50 returns validation error", %{scope: scope} do
      assert {:error, :validation, changeset} =
               Catalog.create_row(scope, %{title: "Bad", source_type: :curated, max_items: 51})

      assert errors_on(changeset)[:max_items] != nil
    end

    test "with max_items at boundary 5 succeeds", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{title: "Min", source_type: :curated, max_items: 5})

      assert row.max_items == 5
    end

    test "with max_items at boundary 50 succeeds", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{title: "Max", source_type: :curated, max_items: 50})

      assert row.max_items == 50
    end

    test "with collection source type succeeds", %{scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "C"})

      assert {:ok, row} =
               Catalog.create_row(scope, %{
                 title: "From Collection",
                 source_type: :collection,
                 source_id: collection.id,
                 max_items: 20
               })

      assert row.source_type == :collection
      assert row.source_id == collection.id
    end

    test "with tag source type succeeds", %{scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "featured"})

      assert {:ok, row} =
               Catalog.create_row(scope, %{
                 title: "By Tag",
                 source_type: :tag,
                 source_id: tag.id,
                 max_items: 20
               })

      assert row.source_type == :tag
    end

    test "with recent source type succeeds", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{
                 title: "New Releases",
                 source_type: :recent,
                 max_items: 20
               })

      assert row.source_type == :recent
    end

    test "with popular source type succeeds", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{
                 title: "Trending",
                 source_type: :popular,
                 max_items: 20
               })

      assert row.source_type == :popular
    end

    test "with continue_watching source type succeeds", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{
                 title: "Continue",
                 source_type: :continue_watching,
                 max_items: 20
               })

      assert row.source_type == :continue_watching
    end
  end

  describe "delete_row/2" do
    test "soft-deletes", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Row", source_type: :curated, max_items: 20})

      assert {:ok, deleted} = Catalog.delete_row(scope, row)
      assert deleted.deleted_at != nil
      assert %{results: []} = Catalog.list_rows(org)
    end
  end

  describe "reorder_rows/2" do
    test "updates positions", %{org: org, scope: scope} do
      {:ok, r1} =
        Catalog.create_row(scope, %{title: "A", source_type: :curated, position: 0, max_items: 20})

      {:ok, r2} =
        Catalog.create_row(scope, %{title: "B", source_type: :curated, position: 1, max_items: 20})

      :ok = Catalog.reorder_rows(scope, [r2.id, r1.id])

      %{results: rows} = Catalog.list_rows(org)
      ids = Enum.map(rows, & &1.id)
      assert ids == [r2.id, r1.id]
    end
  end

  describe "resolve_row_content/3" do
    test "for curated row returns row_items in order", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Curated", source_type: :curated, max_items: 20})

      v1 = insert(:video, organization: org, title: "V1")
      v2 = insert(:video, organization: org, title: "V2")
      {:ok, _} = Catalog.add_item_to_row(scope, row, v1, 1)
      {:ok, _} = Catalog.add_item_to_row(scope, row, v2, 0)

      %{results: videos} = Catalog.resolve_row_content(org, row)
      ids = Enum.map(videos, & &1.id)
      assert ids == [v2.id, v1.id]
    end

    test "for collection row returns collection items", %{org: org, scope: scope} do
      {:ok, collection} = Content.create_collection(scope, %{title: "Series"})
      video = insert(:video, organization: org)
      {:ok, _} = Content.add_video_to_collection(scope, collection, video)

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "From Collection",
          source_type: :collection,
          source_id: collection.id,
          max_items: 20
        })

      %{results: items} = Catalog.resolve_row_content(org, row)
      assert length(items) == 1
      item = hd(items)
      assert item.item_type == :video
      assert item.video.id == video.id
    end

    test "for tag row returns tagged videos", %{org: org, scope: scope} do
      {:ok, tag} = Content.create_tag(scope, %{name: "featured"})
      video = insert(:video, organization: org)
      {:ok, _} = Content.tag_video(scope, video, tag)

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "By Tag",
          source_type: :tag,
          source_id: tag.id,
          max_items: 20
        })

      %{results: videos} = Catalog.resolve_row_content(org, row)
      assert length(videos) == 1
      assert hd(videos).id == video.id
    end

    test "for recent row returns videos newest-first", %{org: org, scope: scope} do
      past = ~U[2026-01-01 00:00:00Z]
      recent = ~U[2026-03-01 00:00:00Z]

      v1 = insert(:video, organization: org, title: "Old", inserted_at: past)
      v2 = insert(:video, organization: org, title: "New", inserted_at: recent)

      {:ok, row} =
        Catalog.create_row(scope, %{title: "Recent", source_type: :recent, max_items: 20})

      %{results: videos} = Catalog.resolve_row_content(org, row)
      assert length(videos) == 2
      ids = Enum.map(videos, & &1.id)
      assert hd(ids) == v2.id
      assert List.last(ids) == v1.id
    end

    test "for continue_watching returns in-progress videos for the viewer", %{
      org: org,
      scope: scope
    } do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Continue",
          source_type: :continue_watching,
          max_items: 20
        })

      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org)
      _other_video = insert(:video, organization: org)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: video,
        position: 45.0,
        completed: false
      )

      result = Catalog.resolve_row_content(org, row, viewer: viewer)
      assert result.total == 1
      assert hd(result.results).video.id == video.id
    end

    test "for continue_watching without viewer returns empty", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Continue",
          source_type: :continue_watching,
          max_items: 20
        })

      assert Catalog.resolve_row_content(org, row) == %{
               results: [],
               page: 1,
               per_page: 25,
               total: 0,
               total_pages: 1
             }
    end
  end

  describe "add_item_to_row/4" do
    setup %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Curated", source_type: :curated, max_items: 20})

      video = insert(:video, organization: org, title: "Item Video")
      %{row: row, video: video}
    end

    test "adds video to curated row", %{scope: scope, row: row, video: video} do
      assert {:ok, item} = Catalog.add_item_to_row(scope, row, video)
      assert item.row_id == row.id
      assert item.video_id == video.id
    end

    test "auto-assigns position when nil", %{org: org, scope: scope, row: row, video: video} do
      {:ok, item1} = Catalog.add_item_to_row(scope, row, video)
      assert item1.position == 0

      video2 = insert(:video, organization: org, title: "Second")
      {:ok, item2} = Catalog.add_item_to_row(scope, row, video2)
      assert item2.position == 1
    end
  end

  describe "remove_item_from_row/3" do
    setup %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Curated", source_type: :curated, max_items: 20})

      video = insert(:video, organization: org, title: "Removable")
      {:ok, _} = Catalog.add_item_to_row(scope, row, video)
      %{row: row, video: video}
    end

    test "removes video and returns :ok", %{scope: scope, row: row, video: video} do
      assert :ok = Catalog.remove_item_from_row(scope, row, video)
    end

    test "removing non-existent item returns {:error, :not_found}", %{
      scope: scope,
      row: row,
      org: org
    } do
      other_video = insert(:video, organization: org, title: "Not Added")
      assert {:error, :not_found} = Catalog.remove_item_from_row(scope, row, other_video)
    end

    test "removed video no longer in list_row_items", %{
      org: org,
      scope: scope,
      row: row,
      video: video
    } do
      :ok = Catalog.remove_item_from_row(scope, row, video)
      %{results: videos} = Catalog.list_row_items(org, row)
      assert videos == []
    end
  end

  describe "list_row_items/3" do
    test "returns videos in position order", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Ordered", source_type: :curated, max_items: 20})

      v1 = insert(:video, organization: org, title: "V1")
      v2 = insert(:video, organization: org, title: "V2")
      {:ok, _} = Catalog.add_item_to_row(scope, row, v1, 1)
      {:ok, _} = Catalog.add_item_to_row(scope, row, v2, 0)

      %{results: videos} = Catalog.list_row_items(org, row)
      ids = Enum.map(videos, & &1.id)
      assert ids == [v2.id, v1.id]
    end

    test "returns pagination struct", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Paged", source_type: :curated, max_items: 20})

      video = insert(:video, organization: org)
      {:ok, _} = Catalog.add_item_to_row(scope, row, video)

      result = Catalog.list_row_items(org, row, page: 1, per_page: 10)
      assert %{results: _, page: 1, per_page: 10, total: 1, total_pages: 1} = result
    end
  end

  describe "reorder_row_items/3" do
    test "updates positions to match new order", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Reorderable", source_type: :curated, max_items: 20})

      v1 = insert(:video, organization: org, title: "First")
      v2 = insert(:video, organization: org, title: "Second")
      v3 = insert(:video, organization: org, title: "Third")
      {:ok, _} = Catalog.add_item_to_row(scope, row, v1, 0)
      {:ok, _} = Catalog.add_item_to_row(scope, row, v2, 1)
      {:ok, _} = Catalog.add_item_to_row(scope, row, v3, 2)

      :ok = Catalog.reorder_row_items(scope, row, [v3.id, v1.id, v2.id])

      %{results: videos} = Catalog.list_row_items(org, row)
      ids = Enum.map(videos, & &1.id)
      assert ids == [v3.id, v1.id, v2.id]
    end
  end

  describe "resolve_row_content/3 - popular" do
    test "for popular row returns videos ordered by inserted_at desc", %{org: org, scope: scope} do
      past = ~U[2026-01-01 00:00:00Z]
      recent = ~U[2026-03-01 00:00:00Z]

      _v1 = insert(:video, organization: org, title: "Old", inserted_at: past)
      v2 = insert(:video, organization: org, title: "New", inserted_at: recent)

      {:ok, row} =
        Catalog.create_row(scope, %{title: "Popular", source_type: :popular, max_items: 20})

      %{results: videos} = Catalog.resolve_row_content(org, row)
      assert length(videos) == 2
      assert hd(videos).id == v2.id
    end
  end

  describe "resolve_row_content_cached/3" do
    test "returns same result as resolve_row_content", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Cached", source_type: :recent, max_items: 20})

      insert(:video, organization: org, title: "Cached Video")

      uncached = Catalog.resolve_row_content(org, row)
      cached = Catalog.resolve_row_content_cached(org, row)

      assert uncached.results == cached.results
      assert uncached.total == cached.total
    end

    test "continue_watching bypasses cache", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Continue",
          source_type: :continue_watching,
          max_items: 20
        })

      viewer = insert(:viewer, organization: org)

      video1 = insert(:video, organization: org)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: video1,
        position: 30.0,
        completed: false
      )

      first = Catalog.resolve_row_content_cached(org, row, viewer: viewer)
      assert first.total == 1

      video2 = insert(:video, organization: org)

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: video2,
        position: 35.0,
        completed: false
      )

      second = Catalog.resolve_row_content_cached(org, row, viewer: viewer)
      assert second.total == 2
    end
  end

  describe "cache invalidation" do
    test "update_row invalidates cache", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Will Update", source_type: :recent, max_items: 20})

      insert(:video, organization: org, title: "V1")

      # Prime the cache
      _cached = Catalog.resolve_row_content_cached(org, row)

      # Update the row (triggers invalidation)
      {:ok, updated_row} = Catalog.update_row(scope, row, %{title: "Updated"})

      # Cache should have been invalidated, so next call re-computes
      result = Catalog.resolve_row_content_cached(org, updated_row)
      assert result.total == 1
    end

    test "add_item_to_row invalidates cache", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Curated Cache", source_type: :curated, max_items: 20})

      # Prime cache with empty result
      cached_before = Catalog.resolve_row_content_cached(org, row)
      assert cached_before.total == 0

      # Add a video (triggers invalidation)
      video = insert(:video, organization: org)
      {:ok, _} = Catalog.add_item_to_row(scope, row, video)

      # Cache invalidated, should show the new video
      cached_after = Catalog.resolve_row_content_cached(org, row)
      assert cached_after.total == 1
    end

    test "remove_item_from_row invalidates cache", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{title: "Remove Cache", source_type: :curated, max_items: 20})

      video = insert(:video, organization: org)
      {:ok, _} = Catalog.add_item_to_row(scope, row, video)

      # Prime cache with 1 item
      cached_before = Catalog.resolve_row_content_cached(org, row)
      assert cached_before.total == 1

      # Remove the video (triggers invalidation)
      :ok = Catalog.remove_item_from_row(scope, row, video)

      # Cache invalidated
      cached_after = Catalog.resolve_row_content_cached(org, row)
      assert cached_after.total == 0
    end
  end

  describe "multi-tenant isolation" do
    test "org A's rows are not visible to org B", %{scope: scope} do
      {:ok, _} =
        Catalog.create_row(scope, %{title: "A's Row", source_type: :curated, max_items: 20})

      org_b = insert(:organization)
      assert %{results: []} = Catalog.list_rows(org_b)
    end
  end
end
