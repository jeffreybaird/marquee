defmodule BobineWeb.Admin.AppearanceLiveTest do
  use BobineWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Bobine.Catalog
  alias Bobine.Catalog.Row

  describe "mount and render" do
    test "admin can access the appearance page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/appearance")
      assert html =~ "Appearance"
      assert html =~ "Preset chooser"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/appearance")
      assert path == ~p"/users/log-in"
    end
  end

  describe "preset drawer" do
    test "drawer opens by default when the catalog is empty", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/appearance")

      # details tag rendered with `open` attribute when catalog_empty? is true.
      assert html =~ ~s(data-test="preset-drawer" open)
      refute html =~ "preset-destructive-warning"
    end

    test "drawer shows destructive warning + overwrite button when the catalog has rows",
         %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      insert(:row,
        organization: org,
        title: "Keep Me",
        source_type: :recent,
        position: 0,
        visible: true
      )

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      # Switch the selected preset so the apply controls surface.
      view
      |> element("button[data-test='preset-card-creator_channel']")
      |> render_click()

      assert has_element?(view, "[data-test='preset-destructive-warning']")
      assert has_element?(view, "[data-test='overwrite-preset-btn']")
      refute has_element?(view, "[data-test='apply-preset-btn']")
    end
  end

  describe "apply_preset (empty catalog)" do
    test "seeds rows from the preset", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> element("button[data-test='preset-card-creator_channel']")
      |> render_click()

      view
      |> element("[data-test='apply-preset-btn']")
      |> render_click()

      {:ok, layout} = Catalog.get_or_create_layout(org)
      assert layout.preset_name == "creator_channel"

      rows = Bobine.Repo.all(from r in Row, where: r.organization_id == ^org.id)
      assert length(rows) >= 2, "expected preset rows to be seeded"
      assert Enum.any?(rows, &(&1.source_type == :continue_watching))
    end
  end

  describe "overwrite_preset (existing catalog)" do
    test "soft-deletes existing rows and seeds preset defaults", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      existing =
        insert(:row,
          organization: org,
          title: "Keep Me",
          source_type: :recent,
          position: 0,
          visible: true
        )

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> element("button[data-test='preset-card-creator_channel']")
      |> render_click()

      view
      |> element("[data-test='overwrite-preset-btn']")
      |> render_click()

      live_rows =
        Bobine.Repo.all(
          from r in Row,
            where: r.organization_id == ^org.id and is_nil(r.deleted_at)
        )

      refute Enum.any?(live_rows, &(&1.id == existing.id)),
             "destructive overwrite should soft-delete the old row"

      assert length(live_rows) >= 2, "expected preset rows to be seeded post-overwrite"
      assert Enum.any?(live_rows, &(&1.source_type == :continue_watching))

      # The original row is still queryable with deleted_at set.
      deleted = Bobine.Repo.get(Row, existing.id)
      assert deleted.deleted_at != nil
    end
  end

  describe "branding form" do
    test "rejects a non-color accent value", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      html =
        view
        |> form("form[phx-submit='save_branding']", organization: %{accent_color_base: "red"})
        |> render_submit()

      assert html =~ "must be an oklch() or hex color"
    end

    test "save_branding persists accent + display font", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> form("form[phx-submit='save_branding']",
        organization: %{
          accent_color_base: "oklch(0.62 0.18 250)",
          display_font: "DM Serif Display"
        }
      )
      |> render_submit()

      reloaded = Bobine.Repo.get!(Bobine.Accounts.Organization, org.id)
      assert reloaded.accent_color_base == "oklch(0.62 0.18 250)"
      assert reloaded.display_font == "DM Serif Display"
    end
  end

  describe "surface color form (absorbed from /admin/branding)" do
    test "renders the theme editor", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      assert has_element?(view, "[data-test='theme-editor']")
      assert has_element?(view, "[data-test='theme-publish-btn']")
    end
  end
end
