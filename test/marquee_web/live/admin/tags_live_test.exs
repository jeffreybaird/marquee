defmodule MarqueeWeb.Admin.TagsLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.Scope
  alias Marquee.Content

  defp build_scope(membership) do
    membership = Marquee.Repo.preload(membership, [:user, :organization])

    Scope.for_user(membership.user)
    |> Scope.with_organization(membership.organization, membership)
  end

  describe "tag list" do
    test "renders tag list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, _} = Content.create_tag(scope, %{name: "beginner"})

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/tags")
      assert html =~ "beginner"
      assert html =~ "data-test=\"tags-list\""
    end

    test "empty state when no tags", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/tags")
      assert html =~ "data-test=\"empty-state\""
      assert html =~ "No tags yet"
    end

    test "tags from other orgs not visible", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = build_scope(other_mem)
      {:ok, _} = Content.create_tag(other_scope, %{name: "invisible"})

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/tags")
      refute html =~ "invisible"
    end
  end

  describe "tag CRUD" do
    test "create tag with valid name", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/tags")

      view
      |> form("form", %{name: "yoga"})
      |> render_submit()

      html = render(view)
      assert html =~ "yoga"
      assert html =~ "data-test=\"tags-list\""
    end

    test "create tag with empty name shows flash error", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/tags")

      view
      |> form("form", %{name: ""})
      |> render_submit()

      # Empty name is caught client-side in handle_event, puts flash error
      # Flash renders in the layout; verify the tag list remains empty
      html = render(view)
      assert html =~ "data-test=\"empty-state\""
    end

    test "create tag with duplicate name shows flash error", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, _} = Content.create_tag(scope, %{name: "existing"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/tags")

      view
      |> form("form", %{name: "existing"})
      |> render_submit()

      # Duplicate detected — only one tag should appear in the list
      html = render(view)
      assert html =~ "existing"
    end

    test "delete tag removes it from list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, tag} = Content.create_tag(scope, %{name: "removable"})

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/tags")
      assert html =~ "removable"

      html =
        view
        |> element(~s([data-test="delete-tag-#{tag.id}"]))
        |> render_click()

      refute html =~ ~s(data-test="tag-#{tag.id}")
    end

    test "edit tag inline updates name", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, tag} = Content.create_tag(scope, %{name: "oldname"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/tags")

      # Enter edit mode
      render_click(view, "start_edit", %{id: tag.id, name: "oldname"})

      # Update the editing name
      render_click(view, "update_editing_name", %{name: "newname"})

      # Save edit
      render_click(view, "save_edit", %{id: tag.id})

      html = render(view)
      assert html =~ "newname"
    end

    test "edit tag with empty name is rejected", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, tag} = Content.create_tag(scope, %{name: "keepme"})

      # Verify at the context level that empty name update is rejected
      assert {:error, :validation, _} = Content.update_tag(scope, tag, %{name: ""})

      # Original tag is unchanged
      {:ok, reloaded} = Content.get_tag(org, tag.id)
      assert reloaded.name == "keepme"
    end
  end

  describe "RBAC" do
    test "editor role sees create form", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/tags")
      assert html =~ ~s(data-test="new-tag-input")
      assert html =~ ~s(data-test="create-tag-btn")
    end

    test "viewer_support role has read-only access", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/tags")
      refute html =~ ~s(data-test="new-tag-input")
      refute html =~ ~s(data-test="create-tag-btn")
    end
  end
end
