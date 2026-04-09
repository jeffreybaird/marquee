defmodule BobineWeb.Admin.SeriesLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bobine.Accounts.Scope
  alias Bobine.Content

  defp build_scope(membership) do
    membership = Bobine.Repo.preload(membership, [:user, :organization])

    Scope.for_user(membership.user)
    |> Scope.with_organization(membership.organization, membership)
  end

  defp setup_editor do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = build_scope(membership)
    %{org: org, membership: membership, scope: scope}
  end

  ## -----------------------------------------------------------------------
  ## Access control
  ## -----------------------------------------------------------------------

  describe "access control" do
    test "editor can access series page", %{conn: _conn} do
      %{membership: membership} = setup_editor()

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/series")
      assert html =~ "Series"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/series")
      assert path == ~p"/users/log-in"
    end

    test "shows new series button for users with manage permission", %{conn: _conn} do
      %{membership: membership} = setup_editor()

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/series")
      assert html =~ ~s(data-test="new-series-btn")
    end
  end

  ## -----------------------------------------------------------------------
  ## Series list
  ## -----------------------------------------------------------------------

  describe "series list" do
    test "renders empty state when no series exist", %{conn: _conn} do
      %{membership: membership} = setup_editor()

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/series")
      assert html =~ ~s(data-test="empty-state")
      assert html =~ "No series yet"
    end

    test "renders series list when series exist", %{conn: _conn} do
      %{org: org, membership: membership, scope: scope} = setup_editor()
      _ = org

      {:ok, _series} = Content.create_series(scope, %{title: "Breaking Code"})

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/series")
      assert html =~ "Breaking Code"
      assert html =~ ~s(data-test="series-list")
    end

    test "series from other orgs are not visible", %{conn: _conn} do
      %{membership: membership} = setup_editor()

      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = build_scope(other_mem)
      {:ok, _} = Content.create_series(other_scope, %{title: "Other Org Series"})

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/series")
      refute html =~ "Other Org Series"
    end
  end

  ## -----------------------------------------------------------------------
  ## Series CRUD
  ## -----------------------------------------------------------------------

  describe "series CRUD" do
    test "creates a series via the form", %{conn: _conn} do
      %{membership: membership} = setup_editor()

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")

      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      html =
        view
        |> form(~s([data-test="series-form"]),
          series: %{title: "My New Show", description: "A description"}
        )
        |> render_submit()

      assert html =~ "My New Show"
      refute html =~ ~s(data-test="series-form")
    end

    test "shows validation error when title is missing", %{conn: _conn} do
      %{membership: membership} = setup_editor()

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")

      view |> element(~s([data-test="new-series-btn"])) |> render_click()

      html =
        view
        |> form(~s([data-test="series-form"]), series: %{title: ""})
        |> render_submit()

      # Form is still visible (didn't save)
      assert html =~ ~s(data-test="series-form")
    end

    test "edits an existing series", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Original Title"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")

      view |> element(~s([data-test="edit-series-#{series.id}"])) |> render_click()

      html =
        view
        |> form(~s([data-test="series-form"]), series: %{title: "Updated Title"})
        |> render_submit()

      assert html =~ "Updated Title"
      refute html =~ "Original Title"
    end

    test "deletes a series", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "To Delete"})

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/series")
      assert html =~ "To Delete"

      html =
        view
        |> element(~s([data-test="delete-series-#{series.id}"]))
        |> render_click()

      refute html =~ "To Delete"
    end

    test "toggles series visibility", %{conn: _conn} do
      %{membership: membership, scope: scope, org: org} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Toggle Me", visible: true})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")

      view
      |> element(~s([data-test="series-visibility-#{series.id}"]))
      |> render_click()

      {:ok, updated} = Content.get_series(org, series.id)
      assert updated.visible == false
    end
  end

  ## -----------------------------------------------------------------------
  ## Series detail (seasons)
  ## -----------------------------------------------------------------------

  describe "series detail view" do
    test "navigates to series detail", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Detail View Test"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")

      html =
        view
        |> element(~s([data-test="view-series-#{series.id}"]))
        |> render_click()

      assert html =~ ~s(data-test="seasons-empty")
      assert html =~ ~s(data-test="back-to-series-list")
    end

    test "back button returns to series list", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Back Test"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")

      view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()

      html =
        view
        |> element(~s([data-test="back-to-series-list"]))
        |> render_click()

      assert html =~ ~s(data-test="series-list")
      refute html =~ ~s(data-test="back-to-series-list")
    end
  end

  ## -----------------------------------------------------------------------
  ## Season CRUD
  ## -----------------------------------------------------------------------

  describe "season CRUD" do
    test "creates a season under a series", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Has Seasons"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()
      view |> element(~s([data-test="new-season-btn"])) |> render_click()

      html =
        view
        |> form(~s([data-test="season-form"]),
          season: %{title: "Pilot Season", season_number: "1"}
        )
        |> render_submit()

      assert html =~ "Pilot Season"
      assert html =~ ~s(data-test="seasons-list")
    end

    test "auto-assigns season number when blank", %{conn: _conn} do
      %{membership: membership, scope: scope, org: org} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Auto Number"})
      {:ok, _s1} = Content.create_season(scope, series, %{title: "Season One"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()
      view |> element(~s([data-test="new-season-btn"])) |> render_click()

      view
      |> form(~s([data-test="season-form"]), season: %{title: "Season Two", season_number: ""})
      |> render_submit()

      %{results: seasons} = Content.list_seasons(org, series)
      assert length(seasons) == 2
      numbers = Enum.map(seasons, & &1.season_number)
      assert 1 in numbers
      assert 2 in numbers
    end

    test "edits a season", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Edit Season Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "Original Season"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()
      view |> element(~s([data-test="edit-season-#{season.id}"])) |> render_click()

      html =
        view
        |> form(~s([data-test="season-form"]),
          season: %{title: "Renamed Season", season_number: "1"}
        )
        |> render_submit()

      assert html =~ "Renamed Season"
      refute html =~ "Original Season"
    end

    test "deletes a season", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Delete Season Series"})
      {:ok, season} = Content.create_season(scope, series, %{title: "Doomed Season"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()

      html =
        view
        |> element(~s([data-test="delete-season-#{season.id}"]))
        |> render_click()

      refute html =~ "Doomed Season"
      assert html =~ ~s(data-test="seasons-empty")
    end

    test "toggles season visibility", %{conn: _conn} do
      %{membership: membership, scope: scope, org: org} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Visibility Series"})

      {:ok, season} =
        Content.create_season(scope, series, %{title: "Visible Season", visible: true})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()

      view
      |> element(~s([data-test="season-visibility-#{season.id}"]))
      |> render_click()

      {:ok, updated} = Content.get_season(org, season.id)
      assert updated.visible == false
    end

    test "lists multiple seasons in number order", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Multi-season"})
      {:ok, _} = Content.create_season(scope, series, %{title: "S1"})
      {:ok, _} = Content.create_season(scope, series, %{title: "S2"})
      {:ok, _} = Content.create_season(scope, series, %{title: "S3"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      html = view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()

      assert html =~ "S1"
      assert html =~ "S2"
      assert html =~ "S3"
    end

    test "season title links to SeasonLive page", %{conn: _conn} do
      %{membership: membership, scope: scope} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Linked"})
      {:ok, season} = Content.create_season(scope, series, %{title: "S1"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element(~s([data-test="open-season-#{season.id}"]))
               |> render_click()

      assert path == "/admin/series/#{series.id}/seasons/#{season.id}"
    end

    test "creates a season without a title — defaults to 'Season <n>'", %{conn: _conn} do
      %{membership: membership, scope: scope, org: org} = setup_editor()

      {:ok, series} = Content.create_series(scope, %{title: "Auto Title"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/series")
      view |> element(~s([data-test="view-series-#{series.id}"])) |> render_click()
      view |> element(~s([data-test="new-season-btn"])) |> render_click()

      view
      |> form(~s([data-test="season-form"]),
        season: %{title: "", season_number: ""}
      )
      |> render_submit()

      %{results: [season]} = Content.list_seasons(org, series)
      assert season.title == "Season 1"
      assert season.season_number == 1
    end
  end
end
