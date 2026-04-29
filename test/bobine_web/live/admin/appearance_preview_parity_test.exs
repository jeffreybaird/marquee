defmodule BobineWeb.Admin.AppearancePreviewParityTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # Markers the shared `viewer_home_body` component is expected to emit on
  # any home-style surface. Exercised against both the real viewer home and
  # the appearance preview's expanded overlay so the two cannot drift —
  # adding a section to the viewer must surface in the preview, and vice
  # versa.
  @canonical_markers [
    ~s(data-test="hero-carousel"),
    ~s(data-test="hero-slide-0"),
    ~s(data-test="hero-primary-cta-0"),
    ~s(data-test="hero-secondary-cta-0"),
    ~s(data-test="hero-pagination"),
    ~s(data-test="hero-dot-0"),
    ~s(class="content-row-title")
  ]

  describe "viewer home and appearance preview share canonical markers" do
    test "both surfaces render the same hero + row primitives", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      membership = insert(:membership, organization: org, role: :admin)

      hero_row = insert(:hero_row, organization: org)

      hero_video =
        insert(:video,
          organization: org,
          title: "Parity Hero",
          description: "Shared component renders identically in both surfaces.",
          mux_status: "ready"
        )

      insert(:hero_slide,
        organization: org,
        row: hero_row,
        video: hero_video,
        position: 0,
        headline: "Parity Hero",
        primary_cta_label: "Watch now",
        secondary_cta_label: "More info",
        show_primary_cta: true,
        show_secondary_cta: true
      )

      content_video =
        insert(:video, organization: org, title: "Row Video", mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Trending Now",
          source_type: :curated,
          visible: true,
          position: 1
        )

      insert(:row_item, organization: org, row: row, video: content_video, position: 0)

      {:ok, _viewer_view, viewer_html} = live(conn_for_viewer(viewer), ~p"/")

      {:ok, admin_view, _admin_html} = live(conn_for(membership), ~p"/admin/appearance")

      expanded_html =
        admin_view
        |> element("[data-test='expand-preview-btn']")
        |> render_click()

      for marker <- @canonical_markers do
        assert viewer_html =~ marker,
               "viewer / missing canonical marker #{marker}"

        assert expanded_html =~ marker,
               "appearance preview missing canonical marker #{marker}"
      end
    end
  end
end
