defmodule BobineWeb.Admin.SeasonLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bobine.Accounts.Scope
  alias Bobine.Content

  defp build_scope(membership) do
    membership = Bobine.Repo.preload(membership, [:user, :organization])

    Scope.for_user(membership.user)
    |> Scope.with_organization(membership.organization, membership)
  end

  defp setup_season do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = build_scope(membership)

    {:ok, series} = Content.create_series(scope, %{title: "Demo Series"})
    {:ok, season} = Content.create_season(scope, series, %{title: "Pilot"})

    %{org: org, membership: membership, scope: scope, series: series, season: season}
  end

  ## -----------------------------------------------------------------------
  ## Access control
  ## -----------------------------------------------------------------------

  describe "access control" do
    test "editor can access season page", %{conn: _conn} do
      %{membership: membership, series: series, season: season} = setup_season()

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      assert html =~ "Pilot"
      assert html =~ ~s(data-test="season-page-title")
    end

    test "redirects when season belongs to a different series", %{conn: _conn} do
      %{membership: membership, scope: scope, series: series} = setup_season()

      {:ok, other_series} = Content.create_series(scope, %{title: "Other"})

      {:ok, other_season} = Content.create_season(scope, other_series, %{title: "Mismatch"})

      assert {:error, {:live_redirect, %{to: "/admin/series"}}} =
               live(
                 conn_for(membership),
                 ~p"/admin/series/#{series.id}/seasons/#{other_season.id}"
               )
    end

    test "redirects when series doesn't exist", %{conn: _conn} do
      %{membership: membership, season: season} = setup_season()

      assert {:error, {:live_redirect, %{to: "/admin/series"}}} =
               live(
                 conn_for(membership),
                 ~p"/admin/series/#{Ecto.UUID.generate()}/seasons/#{season.id}"
               )
    end

    test "redirects when accessing season from another org", %{conn: _conn} do
      %{membership: membership} = setup_season()

      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = build_scope(other_mem)

      {:ok, other_series} = Content.create_series(other_scope, %{title: "Foreign"})
      {:ok, other_season} = Content.create_season(other_scope, other_series, %{title: "S1"})

      assert {:error, {:live_redirect, %{to: "/admin/series"}}} =
               live(
                 conn_for(membership),
                 ~p"/admin/series/#{other_series.id}/seasons/#{other_season.id}"
               )
    end

    test "shows upload and add-existing buttons for users with manage permission",
         %{conn: _conn} do
      %{membership: membership, series: series, season: season} = setup_season()

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      assert html =~ ~s(data-test="upload-episode-btn")
      assert html =~ ~s(data-test="add-existing-btn")
    end
  end

  ## -----------------------------------------------------------------------
  ## Episode list
  ## -----------------------------------------------------------------------

  describe "episode list" do
    test "shows empty state when no episodes", %{conn: _conn} do
      %{membership: membership, series: series, season: season} = setup_season()

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      assert html =~ ~s(data-test="episodes-empty")
      assert html =~ "No episodes yet"
    end

    test "lists episodes ordered by episode_number", %{conn: _conn} do
      %{membership: membership, scope: scope, org: org, series: series, season: season} =
        setup_season()

      v1 = insert(:video, organization: org, title: "First", mux_status: "ready")
      v2 = insert(:video, organization: org, title: "Second", mux_status: "ready")
      v3 = insert(:video, organization: org, title: "Third", mux_status: "ready")

      {:ok, _} = Content.add_episode(scope, season, v1)
      {:ok, _} = Content.add_episode(scope, season, v2)
      {:ok, _} = Content.add_episode(scope, season, v3)

      {:ok, _view, html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      assert html =~ "First"
      assert html =~ "Second"
      assert html =~ "Third"
      assert html =~ ~s(data-test="episodes-list")
    end
  end

  ## -----------------------------------------------------------------------
  ## Existing-video picker
  ## -----------------------------------------------------------------------

  describe "existing video picker" do
    test "opens picker showing only unassigned videos", %{conn: _conn} do
      %{membership: membership, org: org, series: series, season: season} = setup_season()

      _assigned_video = insert_assigned_video(org, series, season)
      free_video = insert(:video, organization: org, title: "Free Video", mux_status: "ready")

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      html = view |> element(~s([data-test="add-existing-btn"])) |> render_click()

      assert html =~ ~s(data-test="episode-video-picker")
      assert html =~ "Free Video"
      assert html =~ ~s(data-test="picker-video-#{free_video.id}")
    end

    test "adds selected videos as episodes", %{conn: _conn} do
      %{membership: membership, org: org, series: series, season: season} = setup_season()

      v1 = insert(:video, organization: org, title: "Add Me 1", mux_status: "ready")
      v2 = insert(:video, organization: org, title: "Add Me 2", mux_status: "ready")

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      view |> element(~s([data-test="add-existing-btn"])) |> render_click()

      view
      |> element(~s([data-test="picker-video-checkbox-#{v1.id}"]))
      |> render_click()

      view
      |> element(~s([data-test="picker-video-checkbox-#{v2.id}"]))
      |> render_click()

      html =
        view
        |> element(~s([data-test="add-selected-episodes-btn"]))
        |> render_click()

      assert html =~ "Add Me 1"
      assert html =~ "Add Me 2"

      episodes = Content.list_episodes(org, season)
      assert length(episodes) == 2
    end

    test "close button closes the picker", %{conn: _conn} do
      %{membership: membership, series: series, season: season} = setup_season()

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      view |> element(~s([data-test="add-existing-btn"])) |> render_click()
      html = view |> element(~s(button[phx-click="close_picker"]), "Cancel") |> render_click()

      refute html =~ ~s(data-test="episode-video-picker")
    end
  end

  ## -----------------------------------------------------------------------
  ## Episode removal
  ## -----------------------------------------------------------------------

  describe "remove episode" do
    test "removes an episode and keeps the underlying video", %{conn: _conn} do
      %{membership: membership, scope: scope, org: org, series: series, season: season} =
        setup_season()

      video = insert(:video, organization: org, title: "Doomed", mux_status: "ready")
      {:ok, episode} = Content.add_episode(scope, season, video)

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      html =
        view
        |> element(~s([data-test="remove-episode-#{episode.id}"]))
        |> render_click()

      refute html =~ "Doomed"

      # Video itself still exists
      assert {:ok, _} = Content.get_video(org, video.id)

      # Episode is gone
      assert Content.list_episodes(org, season) == []
    end

    test "updates the cached episode_count on the season", %{conn: _conn} do
      %{membership: membership, scope: scope, org: org, series: series, season: season} =
        setup_season()

      video = insert(:video, organization: org, mux_status: "ready")
      {:ok, episode} = Content.add_episode(scope, season, video)

      {:ok, reloaded} = Content.get_season(org, season.id)
      assert reloaded.episode_count == 1

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      view
      |> element(~s([data-test="remove-episode-#{episode.id}"]))
      |> render_click()

      {:ok, reloaded} = Content.get_season(org, season.id)
      assert reloaded.episode_count == 0
    end
  end

  ## -----------------------------------------------------------------------
  ## Upload modal opens
  ## -----------------------------------------------------------------------

  describe "upload modal" do
    test "opening the modal renders the file picker", %{conn: _conn} do
      %{membership: membership, series: series, season: season} = setup_season()

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      html = view |> element(~s([data-test="upload-episode-btn"])) |> render_click()

      assert html =~ ~s(data-test="episode-upload-modal")
      assert html =~ ~s(data-test="upload-file-picker")
    end

    test "closing the modal hides it", %{conn: _conn} do
      %{membership: membership, series: series, season: season} = setup_season()

      {:ok, view, _html} =
        live(conn_for(membership), ~p"/admin/series/#{series.id}/seasons/#{season.id}")

      view |> element(~s([data-test="upload-episode-btn"])) |> render_click()

      html =
        view
        |> element(~s([data-test="episode-upload-modal"] button[phx-click="close_upload"]))
        |> render_click()

      refute html =~ ~s(data-test="episode-upload-modal")
    end
  end

  ## -----------------------------------------------------------------------
  ## Helpers
  ## -----------------------------------------------------------------------

  defp insert_assigned_video(org, series, season) do
    video =
      insert(:video,
        organization: org,
        title: "Already an Episode",
        mux_status: "ready"
      )

    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = build_scope(membership)
    _ = series
    {:ok, _} = Content.add_episode(scope, season, video)
    video
  end
end
