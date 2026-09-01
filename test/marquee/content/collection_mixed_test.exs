defmodule Marquee.Content.CollectionMixedTest do
  use Marquee.DataCase

  alias Marquee.Accounts.Scope
  alias Marquee.Content

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    {:ok, collection} = Content.create_collection(scope, %{title: "Mixed Collection"})
    %{org: org, scope: scope, collection: collection}
  end

  ## -----------------------------------------------------------------------
  ## Adding items
  ## -----------------------------------------------------------------------

  describe "add_video_to_collection/3" do
    test "creates item with item_type :video", %{scope: scope, org: org, collection: collection} do
      video = insert(:video, organization: org)
      {:ok, item} = Content.add_video_to_collection(scope, collection, video)

      assert item.item_type == :video
      assert item.video_id == video.id
      assert item.season_id == nil
      assert item.series_id == nil
    end
  end

  describe "add_season_to_collection/3" do
    test "creates item with item_type :season", %{scope: scope, org: _org, collection: collection} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})

      {:ok, item} = Content.add_season_to_collection(scope, collection, season)

      assert item.item_type == :season
      assert item.season_id == season.id
      assert item.video_id == nil
      assert item.series_id == nil
    end

    test "auto-assigns next position after existing items", %{
      scope: scope,
      org: org,
      collection: collection
    } do
      video = insert(:video, organization: org)
      {:ok, _} = Content.add_video_to_collection(scope, collection, video)

      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      {:ok, item} = Content.add_season_to_collection(scope, collection, season)

      assert item.position == 1
    end
  end

  describe "add_series_to_collection/3" do
    test "creates item with item_type :series", %{scope: scope, collection: collection} do
      {:ok, series} = Content.create_series(scope, %{title: "My Series"})
      {:ok, item} = Content.add_series_to_collection(scope, collection, series)

      assert item.item_type == :series
      assert item.series_id == series.id
      assert item.video_id == nil
      assert item.season_id == nil
    end
  end

  describe "mixed position ordering" do
    test "adding video, then season, then series — positions are 0, 1, 2", %{
      scope: scope,
      org: org,
      collection: collection
    } do
      video = insert(:video, organization: org)
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})

      {:ok, item1} = Content.add_video_to_collection(scope, collection, video)
      {:ok, item2} = Content.add_season_to_collection(scope, collection, season)
      {:ok, item3} = Content.add_series_to_collection(scope, collection, series)

      assert item1.position == 0
      assert item2.position == 1
      assert item3.position == 2
    end
  end

  ## -----------------------------------------------------------------------
  ## Listing
  ## -----------------------------------------------------------------------

  describe "list_collection_items/3" do
    test "returns all types in position order", %{scope: scope, org: org, collection: collection} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      video = insert(:video, organization: org)

      {:ok, _} = Content.add_series_to_collection(scope, collection, series, 2)
      {:ok, _} = Content.add_video_to_collection(scope, collection, video, 0)
      {:ok, _} = Content.add_season_to_collection(scope, collection, season, 1)

      %{results: items} = Content.list_collection_items(org, collection)
      assert length(items) == 3
      assert Enum.at(items, 0).item_type == :video
      assert Enum.at(items, 1).item_type == :season
      assert Enum.at(items, 2).item_type == :series
    end

    test "preloads video on video items", %{scope: scope, org: org, collection: collection} do
      video = insert(:video, organization: org)
      {:ok, _} = Content.add_video_to_collection(scope, collection, video)

      %{results: [item]} = Content.list_collection_items(org, collection)
      assert %Marquee.Content.Video{} = item.video
      assert item.video.id == video.id
    end

    test "preloads season with series on season items", %{
      scope: scope,
      org: org,
      collection: collection
    } do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      {:ok, _} = Content.add_season_to_collection(scope, collection, season)

      %{results: [item]} = Content.list_collection_items(org, collection)
      assert %Marquee.Content.Season{} = item.season
      assert item.season.id == season.id
      assert %Marquee.Content.Series{} = item.season.series
      assert item.season.series.id == series.id
    end

    test "preloads series on series items", %{scope: scope, org: org, collection: collection} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, _} = Content.add_series_to_collection(scope, collection, series)

      %{results: [item]} = Content.list_collection_items(org, collection)
      assert %Marquee.Content.Series{} = item.series
      assert item.series.id == series.id
    end

    test "scoped to org", %{scope: scope, org: org, collection: collection} do
      video = insert(:video, organization: org)
      {:ok, _} = Content.add_video_to_collection(scope, collection, video)

      other_org = insert(:organization)
      assert %{results: []} = Content.list_collection_items(other_org, collection)
    end
  end

  ## -----------------------------------------------------------------------
  ## Removing
  ## -----------------------------------------------------------------------

  describe "remove_collection_item/2" do
    test "deletes the item", %{scope: scope, org: org, collection: collection} do
      video = insert(:video, organization: org)
      {:ok, _} = Content.add_video_to_collection(scope, collection, video)

      %{results: [item]} = Content.list_collection_items(org, collection)
      assert :ok = Content.remove_collection_item(scope, item)

      assert %{results: []} = Content.list_collection_items(org, collection)
    end

    test "works for season items", %{scope: scope, org: org, collection: collection} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})
      {:ok, _} = Content.add_season_to_collection(scope, collection, season)

      %{results: [item]} = Content.list_collection_items(org, collection)
      assert :ok = Content.remove_collection_item(scope, item)
      assert %{results: []} = Content.list_collection_items(org, collection)
    end
  end

  ## -----------------------------------------------------------------------
  ## Reordering
  ## -----------------------------------------------------------------------

  describe "reorder_collection_items/3" do
    test "updates positions for mixed types", %{
      scope: scope,
      org: org,
      collection: collection
    } do
      video = insert(:video, organization: org)
      {:ok, series} = Content.create_series(scope, %{title: "Series"})

      {:ok, _} = Content.add_video_to_collection(scope, collection, video, 0)
      {:ok, _} = Content.add_series_to_collection(scope, collection, series, 1)

      %{results: [video_item, series_item]} = Content.list_collection_items(org, collection)

      :ok =
        Content.reorder_collection_items(scope, collection, [series_item.id, video_item.id])

      %{results: [first, second]} = Content.list_collection_items(org, collection)
      assert first.item_type == :series
      assert second.item_type == :video
    end
  end

  ## -----------------------------------------------------------------------
  ## Multi-tenant isolation
  ## -----------------------------------------------------------------------

  describe "multi-tenant isolation" do
    test "collection items on org A not visible from org B", %{
      scope: scope,
      org: _org,
      collection: collection
    } do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})
      {:ok, _} = Content.add_series_to_collection(scope, collection, series)

      other_org = insert(:organization)
      assert %{results: []} = Content.list_collection_items(other_org, collection)
    end
  end
end
