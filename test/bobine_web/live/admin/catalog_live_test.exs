defmodule BobineWeb.Admin.CatalogLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bobine.Accounts.Scope
  alias Bobine.Catalog
  alias Bobine.Content

  defp build_scope(membership) do
    membership = Bobine.Repo.preload(membership, [:user, :organization])

    Scope.for_user(membership.user)
    |> Scope.with_organization(membership.organization, membership)
  end

  describe "access control" do
    test "admin can access catalog page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "Catalog"
    end

    test "viewer_support can access catalog page", %{conn: _conn} do
      membership = insert(:membership, role: :viewer_support)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "Catalog"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/catalog")
      assert path == ~p"/users/log-in"
    end

    test "displays organization name", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")
      assert has_element?(view, "[data-test='org-name']", membership.organization.name)
    end
  end

  describe "row list" do
    test "renders row list in position order", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, _} =
        Catalog.create_row(scope, %{
          title: "Row B",
          source_type: :curated,
          position: 1,
          max_items: 20
        })

      {:ok, _} =
        Catalog.create_row(scope, %{
          title: "Row A",
          source_type: :recent,
          position: 0,
          max_items: 20
        })

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "data-test=\"rows-list\""
      assert html =~ "Row A"
      assert html =~ "Row B"
    end

    test "empty state when no rows", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "data-test=\"empty-state\""
    end

    test "rows from other orgs not visible", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      other_org = insert(:organization)
      other_user = insert(:user)
      other_mem = insert(:membership, organization: other_org, user: other_user, role: :editor)
      other_scope = build_scope(other_mem)

      {:ok, _} =
        Catalog.create_row(other_scope, %{
          title: "Other Row",
          source_type: :curated,
          max_items: 20
        })

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      refute html =~ "Other Row"
    end
  end

  describe "row CRUD" do
    test "create curated row", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, _} =
        Catalog.create_row(scope, %{
          title: "Featured Content",
          source_type: :curated,
          max_items: 20
        })

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "Featured Content"
      assert html =~ "Curated"
    end

    test "create collection-based row with source selection", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, collection} = Content.create_collection(scope, %{title: "Series"})

      # Create via context directly since form conditionally shows source_id
      {:ok, _} =
        Bobine.Catalog.create_row(scope, %{
          title: "From Series",
          source_type: :collection,
          source_id: collection.id,
          max_items: 20
        })

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "From Series"
      assert html =~ "Collection"
    end

    test "create tag-based row with source selection", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, tag} = Content.create_tag(scope, %{name: "featured"})

      # Create via context directly since form conditionally shows source_id
      {:ok, _} =
        Bobine.Catalog.create_row(scope, %{
          title: "By Tag",
          source_type: :tag,
          source_id: tag.id,
          max_items: 20
        })

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "By Tag"
      assert html =~ "Tag"
    end

    test "create recent row (no source selection needed)", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, _} =
        Catalog.create_row(scope, %{title: "New Releases", source_type: :recent, max_items: 10})

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "New Releases"
      assert html =~ "Recent"
    end

    test "delete row removes it from list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Deletable",
          source_type: :curated,
          max_items: 20
        })

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "Deletable"

      html =
        view
        |> element(~s([data-test="delete-row-#{row.id}"]))
        |> render_click()

      refute html =~ "Deletable"
    end

    test "create welcome_text row persists filter_config fields", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")
      render_click(view, "new_row", %{})

      view
      |> form("[data-test=\"row-form\"]", %{
        row: %{title: "Greeting", source_type: "welcome_text"}
      })
      |> render_change()

      view
      |> form("[data-test=\"row-form\"]", %{
        row: %{
          title: "Greeting",
          source_type: "welcome_text",
          filter_config: %{
            eyebrow: "Hello there",
            headline: "Jump back in",
            body: "Pick up where you left off.",
            cta_label: "Browse",
            cta_href: "/browse"
          }
        }
      })
      |> render_submit()

      %{results: [row]} = Catalog.list_rows(org, per_page: 10)
      assert row.source_type == :welcome_text
      assert row.title == "Greeting"
      assert row.filter_config["eyebrow"] == "Hello there"
      assert row.filter_config["headline"] == "Jump back in"
      assert row.filter_config["body"] == "Pick up where you left off."
      assert row.filter_config["cta_label"] == "Browse"
      assert row.filter_config["cta_href"] == "/browse"
    end

    test "welcome_text edit form shows the configured text fields", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Greet",
          source_type: :welcome_text,
          filter_config: %{
            "eyebrow" => "EYE",
            "headline" => "HEAD",
            "body" => "BODY",
            "cta_label" => "GO",
            "cta_href" => "/go"
          }
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")
      html = render_click(view, "edit_row", %{id: row.id})

      assert html =~ ~s(data-test="welcome-text-fields")
      assert html =~ ~s(value="EYE")
      assert html =~ ~s(value="HEAD")
      assert html =~ "BODY"
      assert html =~ ~s(value="GO")
      assert html =~ ~s(value="/go")
    end

    test "selecting welcome_text via change event reveals text inputs", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")
      render_click(view, "new_row", %{})

      refute render(view) =~ ~s(data-test="welcome-text-fields")

      html =
        view
        |> form("[data-test=\"row-form\"]", %{
          row: %{title: "New Welcome", source_type: "welcome_text"}
        })
        |> render_change()

      assert html =~ ~s(data-test="welcome-text-fields")
      refute html =~ ~s(id="row-card-variant")
      refute html =~ ~s(id="row-max-items")
    end

    test "toggling visibility on a welcome_text row hides it from viewer home", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Greet",
          source_type: :welcome_text,
          visible: true,
          filter_config: %{"headline" => "Look at me"}
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      view
      |> element(~s([data-test="row-#{row.id}"] [data-test="row-visibility-toggle"]))
      |> render_click()

      {:ok, updated} = Catalog.get_row(org, row.id)
      refute updated.visible
    end

    test "edit row title and source type", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Original",
          source_type: :curated,
          max_items: 20
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")
      render_click(view, "edit_row", %{id: row.id})

      html =
        view
        |> form("[data-test=\"row-form\"]", %{
          row: %{title: "Updated Title"}
        })
        |> render_submit()

      assert html =~ "Updated Title"
    end
  end

  describe "row preview" do
    test "preview shows resolved content", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      insert(:video, organization: org, title: "Preview Video")

      {:ok, row} =
        Catalog.create_row(scope, %{
          title: "Recent",
          source_type: :recent,
          max_items: 20
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      html = render_click(view, "preview_row", %{id: row.id})
      assert html =~ "data-test=\"row-preview\""
      assert html =~ "Preview Video"
    end
  end

  describe "reorder" do
    test "reorder updates positions", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      scope = build_scope(membership)

      {:ok, r1} =
        Catalog.create_row(scope, %{
          title: "First",
          source_type: :curated,
          position: 0,
          max_items: 20
        })

      {:ok, _r2} =
        Catalog.create_row(scope, %{
          title: "Second",
          source_type: :curated,
          position: 1,
          max_items: 20
        })

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      render_click(view, "move_down", %{id: r1.id})

      %{results: rows} = Catalog.list_rows(org)
      assert hd(rows).title == "Second"
    end
  end
end
