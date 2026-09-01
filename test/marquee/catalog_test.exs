defmodule Marquee.CatalogTest do
  use Marquee.DataCase

  alias Marquee.Accounts.Scope
  alias Marquee.Catalog

  describe "rows" do
    alias Marquee.Catalog.Row

    setup do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      %{org: org, scope: scope}
    end

    test "list_rows/2 returns all rows for the org", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      assert %{results: [found]} = Catalog.list_rows(org)
      assert found.id == row.id
    end

    test "get_row!/1 returns the row with given id", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      assert Catalog.get_row!(row.id).id == row.id
    end

    test "create_row/2 with valid data creates a row", %{scope: scope} do
      valid_attrs = %{
        position: 42,
        visible: true,
        title: "some title",
        source_type: :curated,
        max_items: 20
      }

      assert {:ok, %Row{} = row} = Catalog.create_row(scope, valid_attrs)
      assert row.position == 42
      assert row.visible == true
      assert row.title == "some title"
      assert row.source_type == :curated
    end

    test "create_row/2 with invalid data returns error changeset", %{scope: scope} do
      invalid_attrs = %{title: nil, source_type: nil}
      assert {:error, :validation, %Ecto.Changeset{}} = Catalog.create_row(scope, invalid_attrs)
    end

    test "update_row/3 with valid data updates the row", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      update_attrs = %{
        position: 43,
        visible: false,
        title: "some updated title"
      }

      assert {:ok, %Row{} = row} = Catalog.update_row(scope, row, update_attrs)
      assert row.position == 43
      assert row.visible == false
      assert row.title == "some updated title"
    end

    test "update_row/3 with invalid data returns error changeset", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      assert {:error, :validation, %Ecto.Changeset{}} =
               Catalog.update_row(scope, row, %{title: nil})

      assert Catalog.get_row!(row.id).title == "some title"
    end

    test "delete_row/2 soft-deletes the row", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      assert {:ok, %Row{} = deleted} = Catalog.delete_row(scope, row)
      assert deleted.deleted_at != nil
      assert %{results: []} = Catalog.list_rows(org)
    end

    test "restore_row/1 restores a soft-deleted row", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      {:ok, deleted} = Catalog.delete_row(scope, row)
      assert {:ok, %Row{} = restored} = Catalog.restore_row(deleted)
      assert restored.deleted_at == nil
    end

    test "list_rows_including_deleted/0 returns soft-deleted rows", %{scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "some title",
          source_type: :curated,
          position: 42,
          visible: true,
          max_items: 20
        })

      {:ok, _deleted} = Catalog.delete_row(scope, row)
      assert [found] = Catalog.list_rows_including_deleted()
      assert found.id == row.id
    end

    test "change_row/1 returns a row changeset" do
      row = %Row{}
      assert %Ecto.Changeset{} = Catalog.change_row(row)
    end
  end

  describe "load_catalog_rows_with_content/2" do
    setup do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      %{org: org, scope: scope}
    end

    test "returns rows with their resolved video content", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Curated Row",
          source_type: :curated,
          position: 1,
          visible: true,
          max_items: 20
        })

      video = insert(:video, organization: org, published: true)
      insert(:row_item, organization: org, row: row, video: video, position: 1)

      results = Catalog.load_catalog_rows_with_content(org)
      assert results != []
      matching = Enum.find(results, fn %{row: r} -> r.id == row.id end)
      assert matching != nil
      assert matching.videos != []
    end

    test "excludes hero rows from results", %{org: org, scope: scope} do
      {:ok, _hero_row} =
        Catalog.create_row(scope, %{
          title: "Hero",
          source_type: :hero,
          position: 0,
          visible: true,
          max_items: 5
        })

      results = Catalog.load_catalog_rows_with_content(org)
      hero_results = Enum.filter(results, fn %{row: r} -> r.source_type == :hero end)
      assert hero_results == []
    end

    test "excludes rows with no content", %{org: org, scope: scope} do
      {:ok, empty_row} =
        Catalog.create_row(scope, %{
          title: "Empty Row",
          source_type: :curated,
          position: 2,
          visible: true,
          max_items: 20
        })

      results = Catalog.load_catalog_rows_with_content(org)
      matching = Enum.find(results, fn %{row: r} -> r.id == empty_row.id end)
      assert matching == nil
    end

    test "includes continue watching rows when viewer is provided", %{org: org, scope: scope} do
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, published: true)

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Continue Watching",
          source_type: :continue_watching,
          position: 0,
          visible: true,
          max_items: 20
        })

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: video,
        position: 12.0,
        completed: false
      )

      results_with_viewer = Catalog.load_catalog_rows_with_content(org, viewer: viewer)
      matching_with_viewer = Enum.find(results_with_viewer, fn %{row: r} -> r.id == row.id end)
      assert matching_with_viewer != nil
      assert Enum.any?(matching_with_viewer.videos, &(&1.id == video.id))

      results_without_viewer = Catalog.load_catalog_rows_with_content(org)

      matching_without_viewer =
        Enum.find(results_without_viewer, fn %{row: r} -> r.id == row.id end)

      assert matching_without_viewer == nil
    end
  end

  describe "list_enriched_hero_slides/2" do
    setup do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      %{org: org, scope: scope}
    end

    test "returns slides enriched with video title and description", %{org: org, scope: scope} do
      {:ok, hero_row} =
        Catalog.create_row(scope, %{
          title: "Hero",
          source_type: :hero,
          position: 0,
          visible: true,
          max_items: 5
        })

      video = insert(:video, organization: org, title: "My Video", description: "A great video")

      {:ok, slide} =
        Catalog.create_hero_slide(scope, hero_row, %{
          video_id: video.id,
          position: 0,
          headline: "Watch Now",
          subheadline: "New release"
        })

      enriched = Catalog.list_enriched_hero_slides(org, hero_row)
      assert length(enriched) == 1

      enriched_slide = hd(enriched)
      assert enriched_slide.id == slide.id
      assert enriched_slide.video_id == video.id
      assert enriched_slide.video_title == "My Video"
      assert enriched_slide.video_description == "A great video"
      assert enriched_slide.headline == "Watch Now"
      assert enriched_slide.subheadline == "New release"
    end

    test "returns empty list when hero row has no slides", %{org: org, scope: scope} do
      {:ok, hero_row} =
        Catalog.create_row(scope, %{
          title: "Hero",
          source_type: :hero,
          position: 0,
          visible: true,
          max_items: 5
        })

      assert Catalog.list_enriched_hero_slides(org, hero_row) == []
    end
  end

  describe "resolve_row_content/3 with :upcoming_live_events" do
    setup do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      %{org: org, scope: scope}
    end

    test "returns scheduled live events for the org", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Upcoming Events",
          source_type: :upcoming_live_events,
          position: 0,
          visible: true,
          max_items: 20
        })

      _scheduled =
        insert(:live_event, organization: org, status: "scheduled", title: "Tomorrow Show")

      _live = insert(:live_event, organization: org, status: "live", title: "Live Now")
      _ended = insert(:live_event, organization: org, status: "ended", title: "Old Show")

      %{results: results} = Catalog.resolve_row_content(org, row)

      titles = Enum.map(results, & &1.title)
      assert "Tomorrow Show" in titles
      refute "Live Now" in titles
      refute "Old Show" in titles
    end

    test "returns empty results when no scheduled events", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Upcoming Events",
          source_type: :upcoming_live_events,
          position: 0,
          visible: true,
          max_items: 20
        })

      %{results: results} = Catalog.resolve_row_content(org, row)
      assert results == []
    end

    test "resolve_row_content_cached bypasses cache for upcoming_live_events", %{
      org: org,
      scope: scope
    } do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Upcoming Events",
          source_type: :upcoming_live_events,
          position: 0,
          visible: true,
          max_items: 20
        })

      event =
        insert(:live_event, organization: org, status: "scheduled", title: "Cache Test Show")

      # First call — should return event
      %{results: results_1} = Catalog.resolve_row_content_cached(org, row)
      assert Enum.any?(results_1, &(&1.id == event.id))

      # Delete event from DB and call again — should reflect change (not cached)
      Marquee.Repo.delete!(event)

      %{results: results_2} = Catalog.resolve_row_content_cached(org, row)
      refute Enum.any?(results_2, &(&1.id == event.id))
    end
  end
end
