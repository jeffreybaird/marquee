defmodule Marquee.Content.NewSeasonExpiryTest do
  use Marquee.DataCase, async: true

  alias Marquee.Accounts.Scope
  alias Marquee.Catalog
  alias Marquee.Content
  alias Marquee.Content.Series

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{org: org, scope: scope}
  end

  ## -----------------------------------------------------------------------
  ## new_season_active?/1
  ## -----------------------------------------------------------------------

  describe "new_season_active?/1" do
    test "false when the flag is off" do
      refute Content.new_season_active?(%Series{new_season: false})
    end

    test "true when flag is on with no expiry" do
      assert Content.new_season_active?(%Series{
               new_season: true,
               new_season_expires_at: nil
             })
    end

    test "true when expiry is in the future" do
      future = DateTime.utc_now() |> DateTime.add(7 * 86_400, :second)
      assert Content.new_season_active?(%Series{new_season: true, new_season_expires_at: future})
    end

    test "false when expiry is in the past" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)
      refute Content.new_season_active?(%Series{new_season: true, new_season_expires_at: past})
    end
  end

  ## -----------------------------------------------------------------------
  ## days_until_new_season_expires/1
  ## -----------------------------------------------------------------------

  describe "days_until_new_season_expires/1" do
    test "nil when flag is off" do
      assert Content.days_until_new_season_expires(%Series{new_season: false}) == nil
    end

    test "nil when there is no expiry" do
      assert Content.days_until_new_season_expires(%Series{
               new_season: true,
               new_season_expires_at: nil
             }) == nil
    end

    test "returns whole days remaining" do
      future = DateTime.utc_now() |> DateTime.add(5 * 86_400 + 60, :second)

      assert Content.days_until_new_season_expires(%Series{
               new_season: true,
               new_season_expires_at: future
             }) == 5
    end

    test "returns 0 when expiry has already passed" do
      past = DateTime.utc_now() |> DateTime.add(-60, :second)

      assert Content.days_until_new_season_expires(%Series{
               new_season: true,
               new_season_expires_at: past
             }) == 0
    end
  end

  ## -----------------------------------------------------------------------
  ## Changeset / persistence behavior
  ## -----------------------------------------------------------------------

  describe "update_series with expiry" do
    test "stores the expiry as a UTC datetime", %{scope: scope} do
      {:ok, series} = Content.create_series(scope, %{title: "Hot"})

      future =
        DateTime.utc_now() |> DateTime.add(14 * 86_400, :second) |> DateTime.truncate(:second)

      {:ok, updated} =
        Content.update_series(scope, series, %{
          new_season: true,
          new_season_expires_at: future
        })

      assert updated.new_season == true
      assert DateTime.compare(updated.new_season_expires_at, future) == :eq
    end

    test "clearing new_season also clears the expiry", %{scope: scope} do
      future = DateTime.utc_now() |> DateTime.add(14 * 86_400, :second)

      {:ok, series} =
        Content.create_series(scope, %{
          title: "Toggle",
          new_season: true,
          new_season_expires_at: future
        })

      assert series.new_season_expires_at != nil

      {:ok, off} = Content.update_series(scope, series, %{new_season: false})

      assert off.new_season == false
      assert off.new_season_expires_at == nil
    end
  end

  ## -----------------------------------------------------------------------
  ## :new_seasons row filters expired flags
  ## -----------------------------------------------------------------------

  describe ":new_seasons row resolver with expiry" do
    test "includes series whose expiry is in the future", %{org: org, scope: scope} do
      future = DateTime.utc_now() |> DateTime.add(3 * 86_400, :second)

      {:ok, _hot} =
        Content.create_series(scope, %{
          title: "Future-bound",
          visible: true,
          new_season: true,
          new_season_expires_at: future
        })

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "New Seasons",
          source_type: :new_seasons,
          visible: true,
          max_items: 20
        })

      %{results: results} = Catalog.resolve_row_content(org, row)
      titles = Enum.map(results, & &1.title)
      assert "Future-bound" in titles
    end

    test "excludes series whose expiry has passed", %{org: org, scope: scope} do
      past = DateTime.utc_now() |> DateTime.add(-86_400, :second)

      {:ok, _expired} =
        Content.create_series(scope, %{
          title: "Stale",
          visible: true,
          new_season: true,
          new_season_expires_at: past
        })

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "New Seasons",
          source_type: :new_seasons,
          visible: true,
          max_items: 20
        })

      %{results: results} = Catalog.resolve_row_content(org, row)
      assert results == []
    end

    test "includes series with the flag on but no expiry (permanent)", %{
      org: org,
      scope: scope
    } do
      {:ok, _permanent} =
        Content.create_series(scope, %{
          title: "Always",
          visible: true,
          new_season: true
        })

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "New Seasons",
          source_type: :new_seasons,
          visible: true,
          max_items: 20
        })

      %{results: results} = Catalog.resolve_row_content(org, row)
      titles = Enum.map(results, & &1.title)
      assert "Always" in titles
    end
  end
end
