defmodule BobineWeb.Admin.CollectionsLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bobine.Content
  alias Bobine.Accounts.Scope

  defp build_scope(membership) do
    membership = Bobine.Repo.preload(membership, [:user, :organization])

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
    test "add video to collection", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, collection} = Content.create_collection(scope, %{title: "With Videos"})
      video = insert(:video, organization: org, title: "My Video")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/collections")

      # Navigate to collection detail
      render_click(view, "view_collection", %{id: collection.id})
      assert render(view) =~ "With Videos"

      # Open video picker
      render_click(view, "open_video_picker")

      # Add video
      html = render_click(view, "add_video", %{"video-id" => video.id})
      assert html =~ "My Video"
      assert html =~ ~s(data-test="collection-video-#{video.id}")
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
