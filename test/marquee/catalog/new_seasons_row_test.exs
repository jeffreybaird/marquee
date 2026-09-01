defmodule Marquee.Catalog.NewSeasonsRowTest do
  use Marquee.DataCase, async: true

  alias Marquee.Accounts.Scope
  alias Marquee.Catalog
  alias Marquee.Content

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    {:ok, row} =
      Catalog.create_row(scope, %{
        title: "New Seasons",
        source_type: :new_seasons,
        visible: true,
        max_items: 20
      })

    %{org: org, scope: scope, row: row}
  end

  describe "new_season flag on Series" do
    test "defaults to false on a fresh series", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Default"})
      assert series.new_season == false
    end

    test "update_series can set the flag to true", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Toggle"})
      {:ok, updated} = Content.update_series(scope, series, %{new_season: true})
      assert updated.new_season == true
    end

    test "update_series can clear the flag", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Clear"})
      {:ok, on} = Content.update_series(scope, series, %{new_season: true})
      assert on.new_season == true
      {:ok, off} = Content.update_series(scope, on, %{new_season: false})
      assert off.new_season == false
    end
  end

  describe ":new_seasons row resolution" do
    test "returns series where new_season is true", %{org: org, scope: scope, row: row} do
      {:ok, _flagged} =
        Content.create_series(scope, %{title: "Flagged", new_season: true, visible: true})

      %{results: results} = Catalog.resolve_row_content(org, row)
      titles = Enum.map(results, & &1.title)
      assert "Flagged" in titles
    end

    test "excludes series with new_season false", %{org: org, scope: scope, row: row} do
      {:ok, _unflagged} =
        Content.create_series(scope, %{title: "Unflagged", new_season: false, visible: true})

      {:ok, _flagged} =
        Content.create_series(scope, %{title: "Flagged", new_season: true, visible: true})

      %{results: results} = Catalog.resolve_row_content(org, row)
      titles = Enum.map(results, & &1.title)
      assert "Flagged" in titles
      refute "Unflagged" in titles
    end

    test "excludes soft-deleted series", %{org: org, scope: scope, row: row} do
      {:ok, gone} =
        Content.create_series(scope, %{title: "Gone", new_season: true, visible: true})

      {:ok, _} = Content.delete_series(scope, gone)

      %{results: results} = Catalog.resolve_row_content(org, row)
      assert results == []
    end

    test "excludes non-visible series", %{org: org, scope: scope, row: row} do
      {:ok, _hidden} =
        Content.create_series(scope, %{title: "Hidden", new_season: true, visible: false})

      %{results: results} = Catalog.resolve_row_content(org, row)
      assert results == []
    end

    test "preloads seasons so card renderers don't N+1", %{org: org, scope: scope, row: row} do
      {:ok, series} =
        Content.create_series(scope, %{title: "With Seasons", new_season: true, visible: true})

      {:ok, _s1} = Content.create_season(scope, series, %{title: "S1"})
      {:ok, _s2} = Content.create_season(scope, series, %{title: "S2"})

      %{results: [loaded]} = Catalog.resolve_row_content(org, row)
      assert is_list(loaded.seasons)
      assert length(loaded.seasons) == 2
    end

    test "respects organization scoping", %{scope: scope, row: row} do
      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = Scope.for_user(other_user) |> Scope.with_organization(other_org, other_mem)

      {:ok, _foreign} =
        Content.create_series(other_scope, %{
          title: "Foreign",
          new_season: true,
          visible: true
        })

      %{results: results} = Catalog.resolve_row_content(scope.organization, row)
      titles = Enum.map(results, & &1.title)
      refute "Foreign" in titles
    end

    test "toggling new_season makes a series appear/disappear",
         %{org: org, scope: scope, row: row} do
      {:ok, series} =
        Content.create_series(scope, %{title: "Toggle Me", visible: true})

      assert %{results: []} = Catalog.resolve_row_content(org, row)

      {:ok, on} = Content.update_series(scope, series, %{new_season: true})
      %{results: results} = Catalog.resolve_row_content(org, row)
      assert Enum.any?(results, &(&1.id == on.id))

      {:ok, _off} = Content.update_series(scope, on, %{new_season: false})
      assert %{results: []} = Catalog.resolve_row_content(org, row)
    end

    test "respects max_items limit", %{org: org, scope: scope} do
      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Capped",
          source_type: :new_seasons,
          visible: true,
          max_items: 5
        })

      for i <- 1..7 do
        {:ok, _} =
          Content.create_series(scope, %{title: "S#{i}", new_season: true, visible: true})
      end

      %{results: results} = Catalog.resolve_row_content(org, row)
      assert length(results) == 5
    end
  end
end
