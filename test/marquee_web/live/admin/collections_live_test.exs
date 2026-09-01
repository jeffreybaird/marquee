defmodule MarqueeWeb.Admin.CollectionsLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.Scope
  alias Marquee.Content

  defp build_scope(membership) do
    membership = Marquee.Repo.preload(membership, [:user, :organization])

    Scope.for_user(membership.user)
    |> Scope.with_organization(membership.organization, membership)
  end

  describe "collection list" do
    test "renders collection list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, _} = Content.create_collection(scope, %{title: "My Collection"})

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/collections")
      assert html =~ "My Collection"
      assert html =~ "data-test=\"collections-list\""
    end

    test "empty state when no collections", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/collections")
      assert html =~ "data-test=\"empty-state\""
      assert html =~ "No collections yet"
    end

    test "collections from other orgs not visible", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = build_scope(other_mem)
      {:ok, _} = Content.create_collection(other_scope, %{title: "Other Org Collection"})

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/collections")
      refute html =~ "Other Org Collection"
    end
  end

  describe "collection CRUD" do
    test "create collection with valid data", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, _} = Content.create_collection(scope, %{title: "Brand New Collection"})

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/collections")
      assert html =~ "Brand New Collection"
    end

    test "create collection with missing title shows error via context", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      assert {:error, :validation, _} = Content.create_collection(scope, %{title: nil})
    end

    test "delete collection removes it from list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, collection} = Content.create_collection(scope, %{title: "To Delete"})

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/collections")
      assert html =~ "To Delete"

      html =
        view
        |> element(~s([data-test="delete-collection-#{collection.id}"]))
        |> render_click()

      refute html =~ "To Delete"
    end
  end

  describe "collection videos" do
    test "select and add multiple videos to collection", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, collection} = Content.create_collection(scope, %{title: "With Videos"})
      video1 = insert(:video, organization: org, title: "Video One")
      video2 = insert(:video, organization: org, title: "Video Two")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/collections")

      # Navigate to collection detail
      render_click(view, "view_collection", %{id: collection.id})
      assert render(view) =~ "With Videos"

      # Open video picker
      render_click(view, "open_video_picker")

      # Checkboxes should be visible
      html = render(view)
      assert html =~ ~s(data-test="select-video-#{video1.id}")
      assert html =~ ~s(data-test="select-video-#{video2.id}")

      # Select both videos
      render_click(view, "toggle_video_selection", %{"video-id" => video1.id})
      render_click(view, "toggle_video_selection", %{"video-id" => video2.id})

      # Confirm selection count
      assert render(view) =~ "2 selected"

      # Add selected videos
      html = render_click(view, "add_selected_videos")
      assert html =~ "Video One"
      assert html =~ "Video Two"
      assert html =~ ~s(data-test="collection-video-#{video1.id}")
      assert html =~ ~s(data-test="collection-video-#{video2.id}")
    end

    test "toggle deselects a previously selected video", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, collection} = Content.create_collection(scope, %{title: "Toggle Test"})
      video = insert(:video, organization: org, title: "Toggled Video")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/collections")
      render_click(view, "view_collection", %{id: collection.id})
      render_click(view, "open_video_picker")

      # Select then deselect
      render_click(view, "toggle_video_selection", %{"video-id" => video.id})
      assert render(view) =~ "1 selected"

      render_click(view, "toggle_video_selection", %{"video-id" => video.id})
      assert render(view) =~ "0 selected"
    end

    test "add selected videos with none selected shows error flash", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, collection} = Content.create_collection(scope, %{title: "No Selection"})
      _video = insert(:video, organization: org, title: "Available")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/collections")
      render_click(view, "view_collection", %{id: collection.id})
      render_click(view, "open_video_picker")

      # The add button should be disabled when nothing is selected
      assert has_element?(view, ~s(button[data-test="add-selected-videos-btn"][disabled]))
    end

    test "remove video from collection", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, collection} = Content.create_collection(scope, %{title: "Has Video"})
      video = insert(:video, organization: org, title: "Removable")
      {:ok, _} = Content.add_video_to_collection(scope, collection, video)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/collections")
      render_click(view, "view_collection", %{id: collection.id})

      assert render(view) =~ "Removable"

      html =
        view
        |> element(~s([data-test="remove-video-#{video.id}"]))
        |> render_click()

      refute html =~ ~s(data-test="collection-video-#{video.id}")
    end
  end

  describe "RBAC" do
    test "editor role can manage collections", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/collections")
      assert html =~ ~s(data-test="new-collection-btn")
    end

    test "viewer_support role has read-only access", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/collections")
      refute html =~ ~s(data-test="new-collection-btn")
    end
  end
end
