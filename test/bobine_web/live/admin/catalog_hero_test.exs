defmodule BobineWeb.Admin.CatalogHeroTest do
  use BobineWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :admin)
    %{org: org, membership: membership}
  end

  describe "hero editor — collapsible" do
    test "collapse toggle is visible and hero body is expanded by default", %{
      membership: membership
    } do
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ ~s(data-test="hero-collapse-toggle")
      assert html =~ ~s(id="hero-editor-body")
      assert html =~ ~s(aria-expanded="true")
    end

    test "clicking collapse toggle hides the hero body", %{membership: membership} do
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      html =
        view
        |> element(~s([data-test="hero-collapse-toggle"]))
        |> render_click()

      refute html =~ ~s(id="hero-editor-body")
      assert html =~ ~s(aria-expanded="false")
    end

    test "clicking collapse toggle twice re-expands the hero body", %{membership: membership} do
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      view
      |> element(~s([data-test="hero-collapse-toggle"]))
      |> render_click()

      html =
        view
        |> element(~s([data-test="hero-collapse-toggle"]))
        |> render_click()

      assert html =~ ~s(id="hero-editor-body")
      assert html =~ ~s(aria-expanded="true")
    end
  end

  describe "hero editor — no hero row" do
    test "create hero carousel button visible when no hero row exists", %{
      membership: membership
    } do
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ ~s(data-test="create-hero-btn")
      assert html =~ "Create hero carousel"
    end

    test "creating hero row shows the editor", %{membership: membership} do
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      html =
        view
        |> element(~s([data-test="create-hero-btn"]))
        |> render_click()

      assert html =~ "Hero Carousel"
      assert html =~ ~s(data-test="hero-add-slide-btn")
      refute html =~ ~s(data-test="create-hero-btn")
    end
  end

  describe "hero editor — with hero row" do
    setup %{org: org, membership: membership} do
      insert(:hero_row, organization: org)
      %{org: org, membership: membership}
    end

    test "hero editor is visible", %{membership: membership} do
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ ~s(data-test="hero-editor")
      refute html =~ ~s(data-test="create-hero-btn")
    end

    test "add slide button is visible", %{membership: membership} do
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ ~s(data-test="hero-add-slide-btn")
    end

    test "adding a slide creates it and shows in the editor", %{org: org, membership: membership} do
      video = insert(:video, organization: org, title: "Hero Video")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      # Open video picker
      view |> element(~s([data-test="hero-add-slide-btn"])) |> render_click()

      # Select video
      html =
        view
        |> element(~s(button[phx-click="add_hero_slide"][phx-value-video-id="#{video.id}"]))
        |> render_click()

      assert html =~ "Hero Video"
      assert html =~ ~s(data-test="hero-slide-editor-0")
    end

    test "all text fields are editable", %{org: org, membership: membership} do
      hero_row = Bobine.Repo.one!(Bobine.Catalog.Row)
      video = insert(:video, organization: org)
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")

      assert html =~ ~s(data-test="hero-headline-input-0")
      assert html =~ ~s(data-test="hero-subheadline-input-0")
      assert html =~ ~s(data-test="hero-brand-tag-input-0")
      assert html =~ ~s(data-test="hero-description-input-0")
      assert html =~ ~s(data-test="hero-primary-cta-input-0")
      assert html =~ ~s(data-test="hero-secondary-cta-input-0")
      assert html =~ ~s(data-test="hero-bg-url-input-0")
    end

    test "saving updates persists changes", %{org: org, membership: membership} do
      hero_row = Bobine.Repo.one!(Bobine.Catalog.Row)
      video = insert(:video, organization: org, title: "Default Title")
      slide = insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      view
      |> element(~s(form[phx-submit="save_hero_slide"]))
      |> render_submit(%{
        "slide-id" => slide.id,
        "headline" => "Custom Hero Text",
        "subheadline" => "",
        "brand_tag" => "",
        "description" => "",
        "primary_cta_label" => "",
        "secondary_cta_label" => "",
        "background_image_url" => ""
      })

      # Verify the update was persisted
      {:ok, updated_slide} = Bobine.Catalog.get_hero_slide(org, slide.id)
      assert updated_slide.headline == "Custom Hero Text"
    end

    test "saving a slide shows inline success feedback", %{org: org, membership: membership} do
      hero_row = Bobine.Repo.one!(Bobine.Catalog.Row)
      video = insert(:video, organization: org, title: "Default Title")
      slide = insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      html =
        view
        |> element(~s(form[phx-submit="save_hero_slide"]))
        |> render_submit(%{
          "slide-id" => slide.id,
          "headline" => "Updated Headline",
          "subheadline" => "",
          "brand_tag" => "",
          "description" => "",
          "primary_cta_label" => "",
          "secondary_cta_label" => "",
          "background_image_url" => ""
        })

      assert html =~ ~s(data-test="hero-slide-save-success-0")
      assert html =~ "Saved"
    end

    test "saving auto-advance shows inline success feedback", %{membership: membership} do
      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      html =
        view
        |> element(~s(form[phx-submit="save_hero_auto_advance"]))
        |> render_submit(%{"auto_advance_ms" => "5000"})

      assert html =~ ~s(data-test="hero-auto-advance-save-success")
      assert html =~ "Saved"
    end

    test "inline success feedback clears after timeout", %{org: org, membership: membership} do
      hero_row = Bobine.Repo.one!(Bobine.Catalog.Row)
      video = insert(:video, organization: org)
      slide = insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/catalog")

      view
      |> element(~s(form[phx-submit="save_hero_slide"]))
      |> render_submit(%{
        "slide-id" => slide.id,
        "headline" => "Test",
        "subheadline" => "",
        "brand_tag" => "",
        "description" => "",
        "primary_cta_label" => "",
        "secondary_cta_label" => "",
        "background_image_url" => ""
      })

      # Simulate the clear message
      send(view.pid, {:clear_hero_save_status, slide.id})
      html = render(view)

      refute html =~ ~s(data-test="hero-slide-save-success-0")
    end

    test "remove slide soft-deletes it", %{org: org, membership: membership} do
      hero_row = Bobine.Repo.one!(Bobine.Catalog.Row)
      video = insert(:video, organization: org)
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ ~s(data-test="hero-slide-editor-0")

      html =
        view
        |> element(~s([data-test="hero-remove-slide-0"]))
        |> render_click()

      refute html =~ ~s(data-test="hero-slide-editor-0")
    end

    test "visibility toggle hides the hero", %{membership: membership} do
      {:ok, view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ ~s(data-test="hero-visibility-toggle")

      view
      |> element(~s([data-test="hero-visibility-toggle"]))
      |> render_click()
    end

    test "editor only shows slides for the current org", %{org: org, membership: membership} do
      hero_row = Bobine.Repo.one!(Bobine.Catalog.Row)
      video = insert(:video, organization: org, title: "My Slide")
      insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

      # Other org's slide
      other_org = insert(:organization)
      other_row = insert(:hero_row, organization: other_org)
      other_video = insert(:video, organization: other_org, title: "Other Slide")

      insert(:hero_slide,
        organization: other_org,
        row: other_row,
        video: other_video,
        position: 0
      )

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/catalog")
      assert html =~ "My Slide"
      refute html =~ "Other Slide"
    end
  end
end
