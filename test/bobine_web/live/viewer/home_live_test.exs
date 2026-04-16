defmodule BobineWeb.Viewer.HomeLiveTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET / auth-based routing" do
    test "operator user with a membership is redirected to /admin with their org slug", %{
      conn: conn
    } do
      org = insert(:organization, slug: "studio-42")
      user = insert(:user)
      insert(:membership, organization: org, user: user)

      conn = log_in_user(conn, user)
      assert {:error, {:redirect, %{to: "/admin?org=studio-42"}}} = live(conn, ~p"/")
    end

    test "super admin is redirected to /super even when an org is resolved", %{conn: conn} do
      org = insert(:organization)
      super_admin = insert(:super_admin)
      insert(:membership, organization: org, user: super_admin)

      conn = conn |> log_in_user(super_admin) |> Map.put(:host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: "/super"}}} = live(conn, ~p"/")
    end

    test "viewer hitting / without an org resolved is redirected to their org home", %{conn: conn} do
      org = insert(:organization, slug: "viewer-org")
      viewer = insert(:viewer, organization: org)

      token = Bobine.Viewers.generate_viewer_session_token(viewer)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:viewer_token, token)

      assert {:error, {:redirect, %{to: "/?org=viewer-org"}}} = live(conn, ~p"/")
    end
  end

  describe "GET / as a viewer" do
    test "renders row titles on the homepage", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      # Insert a video so :recent row has content
      insert(:video, organization: org, mux_status: "ready")

      insert(:row,
        organization: org,
        title: "Trending Now",
        source_type: :recent,
        visible: true,
        position: 0
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Trending Now"
    end

    test "renders videos within rows", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, title: "My Movie", mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Curated Picks",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Curated Picks"
      assert html =~ "My Movie"
    end

    test "renders continue watching row for viewer progress", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, title: "Resume Me", mux_status: "ready")

      insert(:row,
        organization: org,
        title: "Continue Watching",
        source_type: :continue_watching,
        visible: true,
        position: 0
      )

      insert(:progress,
        organization: org,
        viewer: viewer,
        video: video,
        position: 33.0,
        completed: false
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Continue Watching"
      assert html =~ "Resume Me"
    end

    test "does not render hidden rows", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      # Insert a video so :recent row has content
      insert(:video, organization: org, mux_status: "ready")

      insert(:row,
        organization: org,
        title: "Public Row",
        source_type: :recent,
        visible: true,
        position: 0
      )

      insert(:row,
        organization: org,
        title: "Secret Row",
        source_type: :recent,
        visible: false,
        position: 1
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Public Row"
      refute html =~ "Secret Row"
    end

    test "shows the welcome state when no rows exist (Stage 5 replaces the old empty banner)",
         %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Find your first favorite"
    end

    test "hides the welcome state when the viewer has in-progress content",
         %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready", duration: 600)

      # Seed a Progress record so list_continue_watching returns a result.
      insert(:progress,
        organization: org,
        viewer: viewer,
        video: video,
        position: 120,
        duration: 600,
        completed: false
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      refute html =~ "Find your first favorite"
    end
  end

  describe "GET / super admin redirect" do
    test "super admin with no org resolved is redirected to /super", %{conn: conn} do
      super_admin = insert(:super_admin)
      conn = log_in_user(conn, super_admin)

      # Visit / without org resolution (no subdomain, no ?org param)
      assert {:error, {:redirect, %{to: "/super"}}} = live(conn, ~p"/")
    end
  end

  describe "homepage layout and data-test attributes" do
    test "viewer layout is rendered", %{conn: _conn} do
      org = insert(:organization, name: "Test Platform")
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="sv-root")
      assert html =~ ~s(data-test="sv-nav")
    end

    test "navigation shows correct items", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="viewer-nav")
      assert html =~ ~s(data-test="nav-home")
      assert html =~ ~s(data-test="nav-browse")
      # Collections nav item deliberately removed — each row has its own "View All" link
      refute html =~ ~s(data-test="nav-collections")
    end

    test "profile avatar visible when logged in", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org, display_name: "Jane")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="profile-avatar")
      refute html =~ ~s(data-test="sign-in-link")
    end

    test "anonymous visit on org subdomain shows landing page with login link", %{conn: conn} do
      org = insert(:organization)

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ ~s(data-test="org-landing-login-link")
      refute html =~ ~s(data-test="profile-avatar")
    end

    test "org name appears in the header brand", %{conn: _conn} do
      org = insert(:organization, name: "StreamCo")
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "StreamCo"
      assert html =~ ~s(data-test="viewer-brand-logo")
    end
  end

  describe "hero carousel" do
    test "hero carousel section is present when hero slides exist", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-carousel")
    end

    test "hero slide elements match the number of hero slides", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)

      for i <- 0..2 do
        video = insert(:video, organization: org, title: "Video #{i}", mux_status: "ready")
        insert(:hero_slide, organization: org, row: hero_row, video: video, position: i)
      end

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-slide-0")
      assert html =~ ~s(data-test="hero-slide-1")
      assert html =~ ~s(data-test="hero-slide-2")
    end

    test "hero has pagination dots", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-pagination")
      assert html =~ ~s(data-test="hero-dot-0")
    end

    test "hero has primary CTA with default label", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-primary-cta-0")
      assert html =~ "Watch now"
    end

    test "hero slide hides elements when show_* flags are false", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)

      video =
        insert(:video,
          organization: org,
          title: "Default Video Title",
          mux_status: "ready",
          mux_playback_id: "pb_h"
        )

      insert(:hero_slide,
        organization: org,
        row: hero_row,
        video: video,
        position: 0,
        headline: "My Headline",
        subheadline: "My Subheadline",
        description: "My Description",
        brand_tag: "My Brand",
        primary_cta_label: "Primary",
        secondary_cta_label: "Secondary",
        show_headline: false,
        show_subheadline: false,
        show_description: false,
        show_brand_tag: false,
        show_primary_cta: false,
        show_secondary_cta: false
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      refute html =~ "My Headline"
      refute html =~ "My Subheadline"
      refute html =~ "My Description"
      refute html =~ "My Brand"
      refute html =~ ~s(data-test="hero-primary-cta-0")
      refute html =~ ~s(data-test="hero-secondary-cta-0")
    end

    test "hero does NOT render when no hero row exists", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      refute html =~ ~s(data-test="hero-carousel")
    end

    test "hero does NOT render when hero row is hidden", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org, visible: false)
      video = insert(:video, organization: org, mux_status: "ready")
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      refute html =~ ~s(data-test="hero-carousel")
    end

    test "hero slide headline shows custom text when set", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org, title: "Default Title", mux_status: "ready")

      insert(:hero_slide,
        organization: org,
        row: hero_row,
        video: video,
        position: 0,
        headline: "Custom Headline"
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Custom Headline"
      refute html =~ "Default Title"
    end

    test "hero slide falls back to video title when headline is blank", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org, title: "Video Title", mux_status: "ready")
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Video Title"
    end

    test "hero CTA links to the correct video", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "/watch/#{video.id}"
    end

    test "maximum 4 slides rendered", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      hero_row = insert(:hero_row, organization: org)

      for i <- 0..3 do
        video = insert(:video, organization: org, mux_status: "ready")
        insert(:hero_slide, organization: org, row: hero_row, video: video, position: i)
      end

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="hero-slide-0")
      assert html =~ ~s(data-test="hero-slide-3")
      refute html =~ ~s(data-test="hero-slide-4")
    end
  end

  describe "catalog rows" do
    test "catalog rows section is present", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Test Row",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="catalog-rows")
    end

    test "rows with no content are not rendered", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:row,
        organization: org,
        title: "Empty Row",
        source_type: :curated,
        visible: true,
        position: 0
      )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      refute html =~ "Empty Row"
    end

    test "content cards have correct links to /watch/:id", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, title: "Linked Video", mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Watch Row",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      # Home page now uses the shared ViewerComponents.content_card
      # which uses the sv-card-* data-test prefix convention
      assert html =~ ~s(data-test="sv-card-#{video.id}")
      assert html =~ "/watch/#{video.id}"
    end

    test "content row has data-test with row id", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "ID Row",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="content-row-#{row.id}")
    end
  end

  describe "view all links on rows" do
    test "popular row has view all link to /browse/popular", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Popular",
          source_type: :popular,
          visible: true,
          position: 0
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="view-all-#{row.id}")
      assert html =~ "/browse/popular"
    end

    test "recent row has view all link to /browse/recent", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "New Releases",
          source_type: :recent,
          visible: true,
          position: 0
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="view-all-#{row.id}")
      assert html =~ "/browse/recent"
    end

    test "collection row has view all link to /collections/:slug", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      collection = insert(:collection, organization: org, slug: "sci-fi")
      video = insert(:video, organization: org, mux_status: "ready")

      insert(:collection_item,
        organization: org,
        collection: collection,
        video: video,
        position: 0
      )

      row =
        insert(:row,
          organization: org,
          title: "Sci-Fi",
          source_type: :collection,
          source_id: collection.id,
          visible: true,
          position: 0
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="view-all-#{row.id}")
      assert html =~ "/collections/sci-fi"
    end

    test "tag row has view all link to /browse?tag=TAG_ID", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      tag = insert(:tag, organization: org, name: "horror")
      video = insert(:video, organization: org, mux_status: "ready")
      insert(:video_tag, organization: org, video: video, tag: tag)

      row =
        insert(:row,
          organization: org,
          title: "Horror",
          source_type: :tag,
          source_id: tag.id,
          visible: true,
          position: 0
        )

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ ~s(data-test="view-all-#{row.id}")
      assert html =~ "/browse?tag=#{tag.id}"
    end

    test "curated row does not have a view all link", %{conn: _conn} do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      video = insert(:video, organization: org, mux_status: "ready")

      row =
        insert(:row,
          organization: org,
          title: "Hand Picked",
          source_type: :curated,
          visible: true,
          position: 0
        )

      insert(:row_item, organization: org, row: row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Hand Picked"
      refute html =~ ~s(data-test="view-all-#{row.id}")
    end
  end

  describe "multi-tenant isolation" do
    test "homepage shows only the current org's content", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      viewer = insert(:viewer, organization: org)

      insert(:video, organization: org, title: "Org Video", mux_status: "ready")
      insert(:video, organization: other_org, title: "Other Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      refute html =~ "Other Video"
    end
  end

  describe "unauthenticated visitor with org" do
    test "operator with org is redirected to admin instead of viewer home", %{conn: conn} do
      org = insert(:organization, slug: "public-platform")
      user = insert(:user)
      insert(:membership, organization: org, user: user)

      conn = log_in_user(conn, user)
      assert {:error, {:redirect, %{to: "/admin?org=public-platform"}}} = live(conn, ~p"/")
    end

    test "shows default landing for unauthenticated visitor when no landing sections exist", %{
      conn: conn
    } do
      org = insert(:organization, name: "Cool Studio")

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ ~s(data-test="org-landing")
      assert html =~ "Cool Studio"
    end

    test "renders configured landing sections when present", %{conn: conn} do
      org = insert(:organization)

      insert(:landing_section,
        organization: org,
        section_type: :header_text,
        position: 0,
        config: %{"headline" => "Welcome stranger", "size" => "large"}
      )

      insert(:landing_section,
        organization: org,
        section_type: :marketing_copy,
        position: 1,
        config: %{
          "headline" => "Why subscribe",
          "body" => "All the things",
          "text_alignment" => "center"
        }
      )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ ~s(data-test="landing-page")
      assert has_element?(view, "[data-test=header-text-section]")
      assert has_element?(view, "[data-test=marketing-copy-section]")
      assert html =~ "Welcome stranger"
      assert html =~ "Why subscribe"
      refute html =~ ~s(data-test="org-landing")
    end

    test "hidden landing sections are not rendered", %{conn: conn} do
      org = insert(:organization)

      insert(:landing_section,
        organization: org,
        section_type: :header_text,
        visible: false,
        position: 0,
        config: %{"headline" => "Hidden section"}
      )

      insert(:landing_section,
        organization: org,
        section_type: :header_text,
        visible: true,
        position: 1,
        config: %{"headline" => "Shown section"}
      )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Shown section"
      refute html =~ "Hidden section"
    end

    test "plan_display section renders org's active plans", %{conn: conn} do
      org = insert(:organization)
      insert(:plan, organization: org, name: "Pro Plan", amount: 999, active: true)

      insert(:landing_section,
        organization: org,
        section_type: :plan_display,
        position: 0,
        config: %{"headline" => "Pricing"}
      )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, view, html} = live(conn, ~p"/")
      assert has_element?(view, "[data-test=plan-display-section]")
      assert html =~ "Pro Plan"
      assert html =~ "$9.99"
    end

    test "faq section renders questions and answers", %{conn: conn} do
      org = insert(:organization)

      insert(:landing_section,
        organization: org,
        section_type: :faq,
        position: 0,
        config: %{
          "headline" => "FAQ",
          "items" => [
            %{"question" => "Cancel anytime?", "answer" => "Yes you can."}
          ]
        }
      )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, view, html} = live(conn, ~p"/")
      assert has_element?(view, "[data-test=faq-section]")
      assert has_element?(view, "[data-test=faq-item-0]")
      assert html =~ "Cancel anytime?"
      assert html =~ "Yes you can."
    end

    test "hero_video section renders <mux-player> with playback id", %{conn: conn} do
      org = insert(:organization)

      insert(:landing_section,
        organization: org,
        section_type: :hero_video,
        position: 0,
        config: %{
          "video_playback_id" => "pb_hero_123",
          "headline" => "Welcome",
          "cta_text" => "Subscribe"
        }
      )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ ~s(data-test="hero-video-section")
      assert html =~ "<mux-player"
      assert html =~ ~s(playback-id="pb_hero_123")
      assert html =~ ~s(stream-type="on-demand")
      refute html =~ "stream.mux.com"
    end

    test "hero_video hides headline/subheadline/CTA when show_* flags are false", %{conn: conn} do
      org = insert(:organization)

      insert(:landing_section,
        organization: org,
        section_type: :hero_video,
        position: 0,
        config: %{
          "video_playback_id" => "pb_hero",
          "headline" => "Hidden Headline",
          "subheadline" => "Hidden Subheadline",
          "cta_text" => "Hidden CTA",
          "show_headline" => false,
          "show_subheadline" => false,
          "show_cta" => false
        }
      )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/")
      refute html =~ "Hidden Headline"
      refute html =~ "Hidden Subheadline"
      refute html =~ "Hidden CTA"
    end

    test "hero_image hides overlay text when show_* flags are false", %{conn: conn} do
      org = insert(:organization)

      insert(:landing_section,
        organization: org,
        section_type: :hero_image,
        position: 0,
        config: %{
          "image_url" => "https://example.com/hero.jpg",
          "headline" => "Hidden Image Headline",
          "subheadline" => "Hidden Image Subheadline",
          "cta_text" => "Hidden Image CTA",
          "show_headline" => false,
          "show_subheadline" => false,
          "show_cta" => false
        }
      )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/")
      refute html =~ "Hidden Image Headline"
      refute html =~ "Hidden Image Subheadline"
      refute html =~ "Hidden Image CTA"
    end

    test "hero_video falls back to <video> for explicit video_url", %{conn: conn} do
      org = insert(:organization)

      insert(:landing_section,
        organization: org,
        section_type: :hero_video,
        position: 0,
        config: %{
          "video_url" => "https://example.com/hero.mp4",
          "headline" => "Hi"
        }
      )

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ ~s(src="https://example.com/hero.mp4")
      refute html =~ "<mux-player"
    end

    test "landing page is org-scoped", %{conn: conn} do
      org_a = insert(:organization)
      org_b = insert(:organization)

      insert(:landing_section,
        organization: org_a,
        section_type: :header_text,
        config: %{"headline" => "Org A only"}
      )

      conn =
        conn
        |> Map.put(:host, "#{org_b.slug}.localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, _view, html} = live(conn, ~p"/")
      refute html =~ "Org A only"
    end
  end

  describe "logged-in viewer without subdomain" do
    test "redirects to / with explicit ?org=<slug> when viewer hits root without subdomain",
         %{conn: conn} do
      org = insert(:organization, slug: "viewer-org")
      viewer = insert(:viewer, organization: org)
      token = Bobine.Viewers.generate_viewer_session_token(viewer)

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Phoenix.ConnTest.init_test_session(%{viewer_token: token})

      assert {:error, {:redirect, %{to: "/?org=viewer-org"}}} = live(conn, ~p"/")
    end

    test "renders viewer home once the ?org= param is present", %{conn: conn} do
      org = insert(:organization, slug: "viewer-org-2", name: "Viewer Org 2")
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, mux_status: "ready")

      insert(:row,
        organization: org,
        title: "Viewer Row",
        source_type: :recent,
        visible: true,
        position: 0
      )

      token = Bobine.Viewers.generate_viewer_session_token(viewer)

      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Phoenix.ConnTest.init_test_session(%{viewer_token: token})

      {:ok, _view, html} = live(conn, ~p"/?org=viewer-org-2")
      assert html =~ "Viewer Org 2"
      assert html =~ "Viewer Row"
    end
  end

  describe "platform marketing page (no org)" do
    test "shows platform marketing when no org resolved", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ ~s(data-test="platform-marketing")
      assert has_element?(view, "[data-test=marketing-headline]")
      assert html =~ "Launch your own streaming platform"
    end

    test "marketing page has login and register links", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "[data-test=marketing-login-link]")
      assert has_element?(view, "[data-test=marketing-register-link]")
      assert has_element?(view, "[data-test=marketing-hero-cta]")
    end

    test "marketing page has features section", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "[data-test=marketing-features]")
    end

    test "marketing page has bottom CTA", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Phoenix.ConnTest.init_test_session(%{})

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "[data-test=marketing-bottom-cta]")
    end
  end

  describe "GET / as an authenticated viewer" do
    alias Bobine.Catalog

    test "shows the welcome state when the viewer has no watch history" do
      org = insert(:organization, name: "Indie House")
      viewer = insert(:viewer, organization: org)

      {:ok, _view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "Find your first favorite"
      assert html =~ "Indie House"
    end

    test "reloads rows when the org's layout is updated via PubSub" do
      org = insert(:organization)
      viewer = insert(:viewer, organization: org)
      insert(:video, organization: org, mux_status: "ready")

      insert(:row,
        organization: org,
        title: "First Title",
        source_type: :recent,
        visible: true,
        position: 0
      )

      {:ok, layout} = Catalog.get_or_create_layout(org)
      {:ok, view, html} = live(conn_for_viewer(viewer), ~p"/")
      assert html =~ "First Title"

      # Broadcasts the new row state; the LiveView should re-query and pick
      # up the renamed row without a full page reload.
      Bobine.Repo.update_all(
        Bobine.Catalog.Row,
        set: [title: "Renamed Row"]
      )

      send(view.pid, {:layout_updated, layout})

      refreshed = render(view)
      assert refreshed =~ "Renamed Row"
    end
  end
end
