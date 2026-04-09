defmodule Bobine.Engagement.WatchlistMixedTest do
  use Bobine.DataCase, async: true

  alias Bobine.Accounts.Scope
  alias Bobine.Content
  alias Bobine.Engagement

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    viewer = insert(:subscribed_viewer, organization: org)
    %{org: org, scope: scope, viewer: viewer}
  end

  ## -----------------------------------------------------------------------
  ## Adding each type
  ## -----------------------------------------------------------------------

  describe "add_to_watchlist/3" do
    test "adds a video", %{org: org, viewer: viewer} do
      video = insert(:video, organization: org)

      assert {:ok, item} = Engagement.add_to_watchlist(org, viewer, video)
      assert item.item_type == :video
      assert item.video_id == video.id
    end

    test "adds a season", %{org: org, scope: scope, viewer: viewer} do
      {:ok, series} = Content.create_series(scope, %{title: "Show"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1", season_number: 1})

      assert {:ok, item} = Engagement.add_to_watchlist(org, viewer, season)
      assert item.item_type == :season
      assert item.season_id == season.id
      assert item.video_id == nil
      assert item.series_id == nil
    end

    test "adds a series", %{org: org, scope: scope, viewer: viewer} do
      {:ok, series} = Content.create_series(scope, %{title: "Show"})

      assert {:ok, item} = Engagement.add_to_watchlist(org, viewer, series)
      assert item.item_type == :series
      assert item.series_id == series.id
      assert item.video_id == nil
      assert item.season_id == nil
    end

    test "duplicate add returns :already_in_watchlist", %{org: org, scope: scope, viewer: viewer} do
      {:ok, series} = Content.create_series(scope, %{title: "Show"})
      assert {:ok, _} = Engagement.add_to_watchlist(org, viewer, series)
      assert {:error, :already_in_watchlist} = Engagement.add_to_watchlist(org, viewer, series)
    end

    test "soft-deleted item is restored on re-add", %{org: org, scope: scope, viewer: viewer} do
      {:ok, season} = create_season(scope, "Restorable")

      {:ok, original} = Engagement.add_to_watchlist(org, viewer, season)
      {:ok, _} = Engagement.remove_from_watchlist(org, viewer, season)
      {:ok, restored} = Engagement.add_to_watchlist(org, viewer, season)

      assert restored.id == original.id
      assert restored.deleted_at == nil
    end
  end

  ## -----------------------------------------------------------------------
  ## list_watchlist preloads everything
  ## -----------------------------------------------------------------------

  describe "list_watchlist/3" do
    test "returns mixed items with all three associations preloaded",
         %{org: org, scope: scope, viewer: viewer} do
      video = insert(:video, organization: org, title: "A video")
      {:ok, series} = Content.create_series(scope, %{title: "A series"})
      {:ok, season} = create_season(scope, "A season")

      {:ok, _} = Engagement.add_to_watchlist(org, viewer, video)
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, season)
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, series)

      %{results: items} = Engagement.list_watchlist(org, viewer)
      assert length(items) == 3

      types = Enum.map(items, & &1.item_type) |> Enum.sort()
      assert types == [:season, :series, :video]

      Enum.each(items, fn item ->
        case item.item_type do
          :video -> assert item.video.title == "A video"
          :season -> assert item.season.title == "A season"
          :series -> assert item.series.title == "A series"
        end
      end)
    end
  end

  ## -----------------------------------------------------------------------
  ## in_watchlist? / remove
  ## -----------------------------------------------------------------------

  describe "in_watchlist?/3 and remove_from_watchlist/3" do
    test "in_watchlist? for season", %{org: org, scope: scope, viewer: viewer} do
      {:ok, season} = create_season(scope, "S1")

      refute Engagement.in_watchlist?(org, viewer, season)
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, season)
      assert Engagement.in_watchlist?(org, viewer, season)
    end

    test "in_watchlist? for series", %{org: org, scope: scope, viewer: viewer} do
      {:ok, series} = Content.create_series(scope, %{title: "Series"})

      refute Engagement.in_watchlist?(org, viewer, series)
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, series)
      assert Engagement.in_watchlist?(org, viewer, series)
    end

    test "remove for season", %{org: org, scope: scope, viewer: viewer} do
      {:ok, season} = create_season(scope, "Bye")
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, season)

      assert {:ok, _} = Engagement.remove_from_watchlist(org, viewer, season)
      refute Engagement.in_watchlist?(org, viewer, season)
    end

    test "remove for series", %{org: org, scope: scope, viewer: viewer} do
      {:ok, series} = Content.create_series(scope, %{title: "Bye Series"})
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, series)

      assert {:ok, _} = Engagement.remove_from_watchlist(org, viewer, series)
      refute Engagement.in_watchlist?(org, viewer, series)
    end
  end

  ## -----------------------------------------------------------------------
  ## Multi-tenant
  ## -----------------------------------------------------------------------

  describe "multi-tenant" do
    test "watchlist items don't leak across orgs", %{org: org, viewer: viewer, scope: scope} do
      {:ok, our_series} = Content.create_series(scope, %{title: "Ours"})
      {:ok, _} = Engagement.add_to_watchlist(org, viewer, our_series)

      other_org = insert(:organization)
      other_viewer = insert(:subscribed_viewer, organization: other_org)

      %{results: items} = Engagement.list_watchlist(other_org, other_viewer)
      assert items == []
    end
  end

  defp create_season(scope, title) do
    {:ok, series} = Content.create_series(scope, %{title: "Series for #{title}"})
    Content.create_season(scope, series, %{title: title, season_number: 1})
  end
end
