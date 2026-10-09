defmodule MarqueeWeb.Admin.AppearanceLiveTest do
  use MarqueeWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Marquee.Branding
  alias Marquee.Branding.Theme
  alias Marquee.Catalog
  alias Marquee.Catalog.Row

  describe "mount and render" do
    test "admin can access the appearance page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/appearance")
      assert html =~ "Appearance"
      assert html =~ "Preset chooser"
      assert has_element?(view, "[data-test='preview-frame']")
      assert has_element?(view, "[data-test='hero-carousel']")
      assert has_element?(view, "[data-test='preview-catalog-rows']")
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/appearance")
      assert path == ~p"/users/log-in"
    end

    test "renders configured hero slide content in the preview", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      hero_row = insert(:hero_row, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Mission Briefing",
          description: "A competitive breakdown for the home-page hero."
        )

      insert(:hero_slide,
        organization: org,
        row: hero_row,
        video: video,
        position: 0,
        headline: "Command Phase",
        brand_tag: "Featured",
        primary_cta_label: "Watch now",
        secondary_cta_label: "More info",
        show_primary_cta: true,
        show_secondary_cta: true
      )

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/appearance")

      assert has_element?(view, "[data-test='hero-carousel']")
      assert html =~ "Command Phase"
      assert has_element?(view, "[data-test='hero-primary-cta-0']", "Watch now")
      assert has_element?(view, "[data-test='hero-dot-0']")
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

      rows = Marquee.Repo.all(from r in Row, where: r.organization_id == ^org.id)
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
        Marquee.Repo.all(
          from r in Row,
            where: r.organization_id == ^org.id and is_nil(r.deleted_at)
        )

      refute Enum.any?(live_rows, &(&1.id == existing.id)),
             "destructive overwrite should soft-delete the old row"

      assert length(live_rows) >= 2, "expected preset rows to be seeded post-overwrite"
      assert Enum.any?(live_rows, &(&1.source_type == :continue_watching))

      # The original row is still queryable with deleted_at set.
      deleted = Marquee.Repo.get(Row, existing.id)
      assert deleted.deleted_at != nil
    end
  end

  describe "unified appearance form" do
    test "rejects a non-color accent value", %{conn: _conn} do
      membership = insert(:membership, role: :admin)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      html =
        view
        |> form("form[phx-submit='save_appearance']",
          organization: %{accent_color_base: "red"}
        )
        |> render_submit()

      assert html =~ "must be an oklch() or hex color"
    end

    test "save_appearance persists brand + theme in a single submit", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> form("form[phx-submit='save_appearance']",
        organization: %{
          accent_color_base: "oklch(0.62 0.18 250)",
          display_font: "DM Serif Display"
        },
        theme: %{
          font_heading: "Playfair Display",
          font_body: "Lora",
          background: "#111111"
        }
      )
      |> render_submit()

      reloaded_org = Marquee.Repo.get!(Marquee.Accounts.Organization, org.id)
      assert reloaded_org.accent_color_base == "oklch(0.62 0.18 250)"
      assert reloaded_org.display_font == "DM Serif Display"

      theme = Marquee.Branding.get_theme_or_default(reloaded_org)
      assert theme.font_heading == "Playfair Display"
      assert theme.font_body == "Lora"
      assert theme.background == "#111111"
    end

    test "renders the theme editor inside the unified form", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      assert has_element?(view, "[data-test='theme-editor']")
      assert has_element?(view, "[data-test='save-branding-btn']")
    end
  end

  describe "preview style uses the shared Theme.build_preview_css_vars/1 builder" do
    # The editor's preview frame and expanded overlay must build their inline
    # style through the same function the viewer site uses, so unsaved
    # accent + display-font overrides cannot drift between the two surfaces.
    test "preview frame style equals the shared builder output after validate_appearance",
         %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      {:ok, _theme} =
        Branding.create_theme(
          Theme.preset_attrs("midnight")
          |> Map.put(:organization_id, org.id)
        )

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      html =
        view
        |> form("form[phx-submit='save_appearance']",
          organization: %{accent_color_base: "#ABCDEF", display_font: "Playfair Display"}
        )
        |> render_change()

      expected =
        Theme.build_preview_css_vars(%{
          theme: Branding.get_theme_or_default(org),
          accent_color_base: "#ABCDEF",
          display_font: "Playfair Display"
        })

      [style] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-test='preview-frame'] > .sv-root")
        |> LazyHTML.attribute("style")

      # The frame's scroll prefix is incidental; only the builder output is
      # the contract.
      assert String.ends_with?(style, expected)
      assert style =~ "--color-accent: #ABCDEF; --color-accent-hover: #ABCDEF"
      assert style =~ "--font-display: 'Playfair Display', Georgia, serif"
    end

    test "expanded overlay style equals the shared builder output", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> form("form[phx-submit='save_appearance']",
        organization: %{accent_color_base: "#ABCDEF", display_font: "Playfair Display"},
        theme: %{background: "#123456"}
      )
      |> render_change()

      html =
        view
        |> element("[data-test='expand-preview-btn']")
        |> render_click()

      expected =
        Theme.build_preview_css_vars(%{
          theme: %{Branding.get_theme_or_default(org) | background: "#123456"},
          accent_color_base: "#ABCDEF",
          display_font: "Playfair Display"
        })

      [style] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-test='preview-expanded-overlay'] > .sv-root")
        |> LazyHTML.attribute("style")

      assert style == expected
      assert style =~ "--sv-bg-primary: #123456"
    end
  end

  describe "expand preview" do
    test "expand button is present on mount", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      assert has_element?(view, "[data-test='expand-preview-btn']")
      refute has_element?(view, "[data-test='preview-expanded-overlay']")
    end

    test "clicking expand button shows the full-screen overlay", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> element("[data-test='expand-preview-btn']")
      |> render_click()

      assert has_element?(view, "[data-test='preview-expanded-overlay']")
      assert has_element?(view, "[data-test='hero-carousel']")
    end

    test "clicking close button dismisses the overlay", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> element("[data-test='expand-preview-btn']")
      |> render_click()

      assert has_element?(view, "[data-test='preview-expanded-overlay']")

      view
      |> element("[data-test='close-preview-expanded']")
      |> render_click()

      refute has_element?(view, "[data-test='preview-expanded-overlay']")
    end

    test "expanded overlay uses the canonical hero_carousel component", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      org = membership.organization
      hero_row = insert(:hero_row, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Mission Briefing",
          description: "A competitive breakdown."
        )

      insert(:hero_slide,
        organization: org,
        row: hero_row,
        video: video,
        position: 0,
        headline: "Expanded View Test",
        show_primary_cta: true,
        show_secondary_cta: true
      )

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view
      |> element("[data-test='expand-preview-btn']")
      |> render_click()

      assert has_element?(view, "[data-test='preview-expanded-overlay']")
      assert has_element?(view, "[data-test='hero-carousel']")
    end

    test "inline preview reuses the canonical hero_carousel + content_row components",
         %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, html} = live(conn_for(membership), ~p"/admin/appearance")

      assert has_element?(view, "[data-test='hero-carousel']")
      assert has_element?(view, "[data-test='preview-catalog-rows']")
      assert html =~ "hero-cta-primary"
      assert html =~ "hero-cta-secondary"
    end

    test "inline preview hides rows while expanded so ids stay unique", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/appearance")

      view |> element("[data-test='expand-preview-btn']") |> render_click()

      assert has_element?(view, "[data-test='preview-expanded-overlay']")
      refute has_element?(view, "[data-test='preview-catalog-rows']")
      assert has_element?(view, "[data-test='preview-expanded-catalog-rows']")
    end
  end
end
