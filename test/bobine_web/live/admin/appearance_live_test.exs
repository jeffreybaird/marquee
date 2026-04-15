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
      assert html =~ "Presets"
    end

    test "shows the split notice pointing to Catalog + Branding", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")
      assert has_element?(view, "[data-test='appearance-split-notice']")
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/appearance")
      assert path == ~p"/users/log-in"
    end
  end

  describe "preset selection" do
    test "preview_preset stages a preview without persisting", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> element("button[data-test='preset-card-learning_platform']")
      |> render_click()

      # Preview state — an "Apply preset" button surfaces.
      assert has_element?(view, "[data-test='apply-preset-btn']")

      # Layout row untouched until apply.
      {:ok, layout} = Catalog.get_or_create_layout(membership.organization)
      assert layout.preset_name == "catalog_cinema"
    end

    test "apply_preset seeds rows from the preset on an empty catalog", %{conn: _conn} do
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

    test "apply_preset does not overwrite an existing catalog", %{conn: _conn} do
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
      |> element("[data-test='apply-preset-btn']")
      |> render_click()

      rows = Bobine.Repo.all(from r in Row, where: r.organization_id == ^org.id)
      assert Enum.any?(rows, &(&1.id == existing.id))
      # Preset did not duplicate rows on top of the existing catalog.
      assert length(rows) == 1
    end
  end

  describe "branding form" do
    test "rejects a non-color accent value", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      html =
        view
        |> form("form", organization: %{accent_color_base: "red"})
        |> render_submit()

      assert html =~ "must be an oklch() or hex color"
    end

    test "save_branding persists accent + display font", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> form("form",
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
end
