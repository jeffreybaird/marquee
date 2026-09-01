defmodule Marquee.Catalog.HeroTest do
  use Marquee.DataCase

  alias Marquee.Accounts.Scope
  alias Marquee.Catalog
  alias Marquee.Catalog.HeroSlide

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{org: org, scope: scope}
  end

  # ── Schema tests ──────────────────────────────────────────────────────

  describe "HeroSlide changeset" do
    test "valid attrs produce a valid changeset" do
      org = insert(:organization)
      row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org)

      changeset =
        HeroSlide.changeset(%HeroSlide{}, %{
          organization_id: org.id,
          row_id: row.id,
          video_id: video.id,
          position: 0
        })

      assert changeset.valid?
    end

    test "requires organization_id, row_id, video_id" do
      changeset = HeroSlide.changeset(%HeroSlide{}, %{})
      errors = errors_on(changeset)
      assert errors[:organization_id]
      assert errors[:row_id]
      assert errors[:video_id]
    end

    test "position must be 0-3" do
      org = insert(:organization)
      row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org)

      changeset =
        HeroSlide.changeset(%HeroSlide{}, %{
          organization_id: org.id,
          row_id: row.id,
          video_id: video.id,
          position: 4
        })

      assert errors_on(changeset)[:position]
    end

    test "all text fields are optional" do
      org = insert(:organization)
      row = insert(:hero_row, organization: org)
      video = insert(:video, organization: org)

      changeset =
        HeroSlide.changeset(%HeroSlide{}, %{
          organization_id: org.id,
          row_id: row.id,
          video_id: video.id,
          position: 0
        })

      assert changeset.valid?
      refute Map.has_key?(errors_on(changeset), :headline)
      refute Map.has_key?(errors_on(changeset), :subheadline)
    end
  end

  # ── Hero row ──────────────────────────────────────────────────────────

  describe "create_hero_row/2" do
    test "creates a row with source_type :hero", %{scope: scope} do
      assert {:ok, row} = Catalog.create_hero_row(scope, %{})
      assert row.source_type == :hero
      assert row.visible == true
    end

    test "returns {:error, :already_exists} if hero row already exists", %{scope: scope} do
      {:ok, _} = Catalog.create_hero_row(scope, %{})
      assert {:error, :already_exists} = Catalog.create_hero_row(scope, %{})
    end
  end

  describe "get_hero_row/1" do
    test "returns the hero row", %{org: org, scope: scope} do
      {:ok, created} = Catalog.create_hero_row(scope, %{})
      assert {:ok, found} = Catalog.get_hero_row(org)
      assert found.id == created.id
    end

    test "returns {:error, :not_found} when none exists", %{org: org} do
      assert {:error, :not_found} = Catalog.get_hero_row(org)
    end
  end

  # ── Hero slides CRUD ──────────────────────────────────────────────────

  describe "create_hero_slide/3" do
    setup %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org)
      %{hero_row: row, video: video}
    end

    test "creates a slide linked to a video", %{scope: scope, hero_row: row, video: video} do
      assert {:ok, slide} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})
      assert slide.video_id == video.id
      assert slide.row_id == row.id
    end

    test "auto-assigns position", %{org: org, scope: scope, hero_row: row, video: video} do
      {:ok, slide1} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})
      assert slide1.position == 0

      video2 = insert(:video, organization: org)
      {:ok, slide2} = Catalog.create_hero_slide(scope, row, %{video_id: video2.id})
      assert slide2.position == 1
    end

    test "with 4 existing slides returns {:error, :hero_limit_reached, _}", %{
      org: org,
      scope: scope,
      hero_row: row
    } do
      for i <- 0..3 do
        v = insert(:video, organization: org)
        {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: v.id, position: i})
      end

      extra_video = insert(:video, organization: org)

      assert {:error, :hero_limit_reached, %{limit: 4, current: 4}} =
               Catalog.create_hero_slide(scope, row, %{video_id: extra_video.id})
    end
  end

  describe "update_hero_slide/3" do
    setup %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org)
      {:ok, slide} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})
      %{hero_row: row, slide: slide}
    end

    test "updates text fields", %{scope: scope, slide: slide} do
      {:ok, updated} =
        Catalog.update_hero_slide(scope, slide, %{
          headline: "New Headline",
          subheadline: "Now streaming"
        })

      assert updated.headline == "New Headline"
      assert updated.subheadline == "Now streaming"
    end

    test "with nil headline preserves nil", %{scope: scope, slide: slide} do
      {:ok, updated} = Catalog.update_hero_slide(scope, slide, %{headline: nil})
      assert is_nil(updated.headline)
    end
  end

  describe "delete_hero_slide/2" do
    setup %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org)
      {:ok, slide} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})
      %{hero_row: row, slide: slide}
    end

    test "soft-deletes the slide", %{scope: scope, slide: slide} do
      {:ok, deleted} = Catalog.delete_hero_slide(scope, slide)
      assert deleted.deleted_at != nil
    end

    test "soft-deleted slide no longer counted toward limit", %{
      org: org,
      scope: scope,
      hero_row: row,
      slide: slide
    } do
      {:ok, _} = Catalog.delete_hero_slide(scope, slide)

      # Should be able to add new slides since the deleted one doesn't count
      video2 = insert(:video, organization: org)
      assert {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video2.id})
    end
  end

  describe "reorder_hero_slides/3" do
    test "updates positions", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)
      {:ok, s1} = Catalog.create_hero_slide(scope, row, %{video_id: v1.id, position: 0})
      {:ok, s2} = Catalog.create_hero_slide(scope, row, %{video_id: v2.id, position: 1})

      :ok = Catalog.reorder_hero_slides(scope, row, [s2.id, s1.id])

      slides = Catalog.list_hero_slides(org, row)
      ids = Enum.map(slides, & &1.id)
      assert ids == [s2.id, s1.id]
    end
  end

  describe "list_hero_slides/2" do
    test "returns slides in position order", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      v1 = insert(:video, organization: org)
      v2 = insert(:video, organization: org)
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: v1.id, position: 1})
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: v2.id, position: 0})

      slides = Catalog.list_hero_slides(org, row)
      positions = Enum.map(slides, & &1.position)
      assert positions == [0, 1]
    end

    test "excludes soft-deleted slides", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      v = insert(:video, organization: org)
      {:ok, slide} = Catalog.create_hero_slide(scope, row, %{video_id: v.id})
      {:ok, _} = Catalog.delete_hero_slide(scope, slide)

      assert [] = Catalog.list_hero_slides(org, row)
    end
  end

  # ── Resolve ───────────────────────────────────────────────────────────

  describe "resolve_hero_slides/1" do
    test "returns resolved data with fallbacks", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org, title: "My Video", mux_playback_id: "pb_abc")
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      %{slides: [slide]} = Catalog.resolve_hero_slides(org)
      assert slide.headline == "My Video"
      assert slide.primary_cta_label == "Watch now"
      assert slide.secondary_cta_label == "More info"
      assert slide.primary_cta_path == "/watch/#{video.id}"
    end

    test "uses video title when headline is blank", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org, title: "Fallback Title")
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      %{slides: [slide]} = Catalog.resolve_hero_slides(org)
      assert slide.headline == "Fallback Title"
    end

    test "uses video description when description is blank", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org, description: "Video desc")
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      %{slides: [slide]} = Catalog.resolve_hero_slides(org)
      assert slide.description == "Video desc"
    end

    test "uses Mux thumbnail when background_image_url is nil", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org, mux_playback_id: "pb_xyz")
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      %{slides: [slide]} = Catalog.resolve_hero_slides(org)
      assert slide.background_image_url =~ "image.mux.com/pb_xyz"
    end

    test "uses custom text when provided", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org, title: "Default Title")

      {:ok, _} =
        Catalog.create_hero_slide(scope, row, %{
          video_id: video.id,
          headline: "Custom Headline",
          primary_cta_label: "Play Episode 1"
        })

      %{slides: [slide]} = Catalog.resolve_hero_slides(org)
      assert slide.headline == "Custom Headline"
      assert slide.primary_cta_label == "Play Episode 1"
    end

    test "returns empty slides when no hero row exists", %{org: org} do
      assert %{slides: []} = Catalog.resolve_hero_slides(org)
    end

    test "returns empty slides when hero row is not visible", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org)
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      # Hide the hero row
      {:ok, _} = Catalog.update_row(scope, row, %{visible: false})

      assert %{slides: []} = Catalog.resolve_hero_slides(org)
    end

    test "resolve_hero_slides_cached returns same result as uncached", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org)
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      uncached = Catalog.resolve_hero_slides(org)
      cached = Catalog.resolve_hero_slides_cached(org)
      assert uncached == cached
    end
  end

  # ── Cache invalidation ───────────────────────────────────────────────

  describe "cache invalidation" do
    test "cache is invalidated when a slide is created", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})

      # Prime the cache with empty result
      %{slides: cached_before} = Catalog.resolve_hero_slides_cached(org)
      assert cached_before == []

      # Create a slide
      video = insert(:video, organization: org)
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      # Cache should be invalidated, should show the new slide
      %{slides: cached_after} = Catalog.resolve_hero_slides_cached(org)
      assert length(cached_after) == 1
    end

    test "cache is invalidated when a slide is updated", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org, title: "Original")
      {:ok, slide} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      # Prime cache
      _ = Catalog.resolve_hero_slides_cached(org)

      # Update slide
      {:ok, _} = Catalog.update_hero_slide(scope, slide, %{headline: "Updated"})

      # Cache should reflect the update
      %{slides: [resolved]} = Catalog.resolve_hero_slides_cached(org)
      assert resolved.headline == "Updated"
    end
  end

  # ── Multi-tenant isolation ───────────────────────────────────────────

  describe "multi-tenant isolation" do
    test "hero row on org A not visible from org B context", %{scope: scope} do
      {:ok, _} = Catalog.create_hero_row(scope, %{})

      org_b = insert(:organization)
      assert {:error, :not_found} = Catalog.get_hero_row(org_b)
    end

    test "hero slides on org A not accessible from org B", %{org: org, scope: scope} do
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      video = insert(:video, organization: org)
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      org_b = insert(:organization)
      assert %{slides: []} = Catalog.resolve_hero_slides(org_b)
    end
  end

  # ── Events and audit ─────────────────────────────────────────────────

  describe "events" do
    setup %{org: org, scope: scope} do
      Marquee.Events.subscribe(org.id)
      {:ok, row} = Catalog.create_hero_row(scope, %{})
      %{hero_row: row}
    end

    test "creating a hero slide broadcasts :hero_slide_created", %{
      org: org,
      scope: scope,
      hero_row: row
    } do
      video = insert(:video, organization: org)
      {:ok, _} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})

      assert_received {:marquee_event, {:hero_slide_created, _slide}, _scope}
    end

    test "updating a hero slide broadcasts :hero_slide_updated", %{
      org: org,
      scope: scope,
      hero_row: row
    } do
      video = insert(:video, organization: org)
      {:ok, slide} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})
      {:ok, _} = Catalog.update_hero_slide(scope, slide, %{headline: "Changed"})

      assert_received {:marquee_event, {:hero_slide_updated, _slide}, _scope}
    end

    test "deleting a hero slide broadcasts :hero_slide_deleted", %{
      org: org,
      scope: scope,
      hero_row: row
    } do
      video = insert(:video, organization: org)
      {:ok, slide} = Catalog.create_hero_slide(scope, row, %{video_id: video.id})
      {:ok, _} = Catalog.delete_hero_slide(scope, slide)

      assert_received {:marquee_event, {:hero_slide_deleted, _slide}, _scope}
    end
  end
end
