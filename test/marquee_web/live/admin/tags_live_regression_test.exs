defmodule MarqueeWeb.Admin.TagsLiveRegressionTest do
  @moduledoc """
  Regression coverage for the tags page:

    * D3: flash messages (e.g. the duplicate-tag error) are rendered on the page.
    * D4: the inline edit input lives inside a `<form>`, and submitting that
      form saves the new name.
  """
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.Scope
  alias Marquee.Content

  @create_form "form[phx-submit=create_tag]"

  defp setup_editor do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    membership = Marquee.Repo.preload(membership, [:user, :organization])

    scope =
      Scope.for_user(membership.user)
      |> Scope.with_organization(membership.organization, membership)

    %{org: org, membership: membership, scope: scope}
  end

  describe "flash messages (D3)" do
    test "duplicate tag name shows a visible error flash" do
      %{membership: membership, scope: scope} = setup_editor()
      {:ok, _} = Content.create_tag(scope, %{name: "existing"})

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/tags")

      view |> form(@create_form, %{name: "existing"}) |> render_submit()

      assert has_element?(view, "#flash-error", "A tag with this name already exists.")
    end

    test "name matching an existing tag with a different slug shows the error flash" do
      %{org: org, membership: membership} = setup_editor()
      existing = insert(:tag, organization: org, name: "existing")
      refute existing.slug == "existing"

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/tags")

      view |> form(@create_form, %{name: "Existing"}) |> render_submit()

      assert has_element?(view, "#flash-error", "A tag with this name already exists.")
      assert %{results: [only]} = Content.list_tags(org)
      assert only.id == existing.id
    end

    test "successful create shows a visible info flash" do
      %{membership: membership} = setup_editor()

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/tags")

      view |> form(@create_form, %{name: "fresh"}) |> render_submit()

      assert has_element?(view, "#flash-info", "Tag created.")
    end
  end

  describe "inline edit form (D4)" do
    test "edit input is inside a form and submitting it saves the new name" do
      %{org: org, membership: membership, scope: scope} = setup_editor()
      {:ok, tag} = Content.create_tag(scope, %{name: "oldname"})
      row = ~s([data-test="tag-#{tag.id}"])

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/tags")

      view |> element("#{row} button", "Edit") |> render_click()

      assert has_element?(view, ~s(#{row} form input[name="name"]))

      view
      |> form("#{row} form", %{name: "newname"})
      |> render_submit()

      assert {:ok, %{name: "newname"}} = Content.get_tag(org, tag.id)
      assert has_element?(view, row, "newname")
      refute has_element?(view, ~s(#{row} input[name="name"]))
    end
  end
end
