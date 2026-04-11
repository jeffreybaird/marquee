defmodule Bobine.LandingPageTest do
  use Bobine.DataCase

  alias Bobine.Accounts.Scope
  alias Bobine.LandingPage
  alias Bobine.LandingPage.LandingSection

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{org: org, scope: scope}
  end

  describe "create_landing_section/2" do
    test "creates a header_text section with valid config", %{scope: scope} do
      assert {:ok, %LandingSection{} = section} =
               LandingPage.create_landing_section(scope, %{
                 section_type: :header_text,
                 config: %{"headline" => "Hello"}
               })

      assert section.section_type == :header_text
      assert section.config["headline"] == "Hello"
      assert section.position == 0
      assert section.visible == true
    end

    test "auto-assigns the next position", %{scope: scope} do
      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "First"}
        })

      {:ok, second} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Second"}
        })

      assert second.position == 1
    end

    test "stringifies atom keys in config", %{scope: scope} do
      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{headline: "Atomic"}
        })

      assert section.config["headline"] == "Atomic"
    end

    test "allows hero_video stub without video source so operator can edit",
         %{scope: scope} do
      assert {:ok, section} =
               LandingPage.create_landing_section(scope, %{
                 section_type: :hero_video,
                 config: %{"headline" => "Watch"}
               })

      assert section.section_type == :hero_video
    end

    test "allows hero_image stub without image_url so operator can edit",
         %{scope: scope} do
      assert {:ok, section} =
               LandingPage.create_landing_section(scope, %{
                 section_type: :hero_image,
                 config: %{"headline" => "Welcome"}
               })

      assert section.section_type == :hero_image
    end

    test "rejects content_row without recognized source_type", %{scope: scope} do
      assert {:error, :validation, changeset} =
               LandingPage.create_landing_section(scope, %{
                 section_type: :content_row,
                 config: %{"title" => "Bad"}
               })

      assert errors_on(changeset).config != []
    end

    test "rejects collection content_row without source_id", %{scope: scope} do
      assert {:error, :validation, changeset} =
               LandingPage.create_landing_section(scope, %{
                 section_type: :content_row,
                 config: %{"source_type" => "collection"}
               })

      assert "collection source requires source_id" in errors_on(changeset).config
    end

    test "rejects faq missing items", %{scope: scope} do
      assert {:error, :validation, changeset} =
               LandingPage.create_landing_section(scope, %{
                 section_type: :faq,
                 config: %{"headline" => "FAQ"}
               })

      assert errors_on(changeset).config != []
    end

    test "accepts faq with valid items", %{scope: scope} do
      assert {:ok, _} =
               LandingPage.create_landing_section(scope, %{
                 section_type: :faq,
                 config: %{
                   "headline" => "FAQ",
                   "items" => [%{"question" => "Q?", "answer" => "A."}]
                 }
               })
    end
  end

  describe "list_landing_sections/1" do
    test "returns visible sections in position order", %{scope: scope, org: org} do
      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          position: 2,
          config: %{"headline" => "Third"}
        })

      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          position: 0,
          config: %{"headline" => "First"}
        })

      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          position: 1,
          config: %{"headline" => "Second"}
        })

      headlines = org |> LandingPage.list_landing_sections() |> Enum.map(& &1.config["headline"])
      assert headlines == ["First", "Second", "Third"]
    end

    test "excludes hidden sections", %{scope: scope, org: org} do
      {:ok, visible} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Visible"}
        })

      {:ok, hidden} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          visible: false,
          config: %{"headline" => "Hidden"}
        })

      ids = org |> LandingPage.list_landing_sections() |> Enum.map(& &1.id)
      assert visible.id in ids
      refute hidden.id in ids
    end

    test "is scoped to organization", %{scope: scope, org: org} do
      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Mine"}
        })

      other_org = insert(:organization)
      assert LandingPage.list_landing_sections(other_org) == []
      assert length(LandingPage.list_landing_sections(org)) == 1
    end
  end

  describe "list_landing_sections_admin/1" do
    test "includes hidden sections", %{scope: scope, org: org} do
      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          visible: false,
          config: %{"headline" => "Hidden"}
        })

      assert [%{visible: false}] = LandingPage.list_landing_sections_admin(org)
    end

    test "excludes soft-deleted sections", %{scope: scope, org: org} do
      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Doomed"}
        })

      {:ok, _} = LandingPage.delete_landing_section(scope, section)
      assert LandingPage.list_landing_sections_admin(org) == []
    end
  end

  describe "update_landing_section/3" do
    test "updates config and visibility", %{scope: scope} do
      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Old"}
        })

      assert {:ok, updated} =
               LandingPage.update_landing_section(scope, section, %{
                 config: %{"headline" => "New"},
                 visible: false
               })

      assert updated.config["headline"] == "New"
      assert updated.visible == false
    end

    test "returns validation error for bad config", %{scope: scope} do
      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :content_row,
          config: %{"source_type" => "recent", "title" => "Recent"}
        })

      assert {:error, :validation, _} =
               LandingPage.update_landing_section(scope, section, %{
                 config: %{"source_type" => "bogus"}
               })
    end
  end

  describe "delete_landing_section/2" do
    test "soft-deletes the section", %{scope: scope} do
      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "Bye"}
        })

      assert {:ok, deleted} = LandingPage.delete_landing_section(scope, section)
      assert deleted.deleted_at != nil
    end
  end

  describe "reorder_landing_sections/2" do
    test "updates positions to match the given order", %{scope: scope, org: org} do
      {:ok, a} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "A"}
        })

      {:ok, b} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "B"}
        })

      {:ok, c} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "C"}
        })

      assert :ok = LandingPage.reorder_landing_sections(scope, [c.id, a.id, b.id])

      headlines = org |> LandingPage.list_landing_sections() |> Enum.map(& &1.config["headline"])
      assert headlines == ["C", "A", "B"]
    end
  end

  describe "resolve_landing_section/2" do
    test "marketing_copy returns config as-is", %{scope: scope, org: org} do
      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :marketing_copy,
          config: %{"headline" => "Why us"}
        })

      resolved = LandingPage.resolve_landing_section(org, section)
      assert resolved.config["headline"] == "Why us"
      refute Map.has_key?(resolved.config, "items")
    end

    test "content_row resolves recent videos", %{scope: scope, org: org} do
      v1 = insert(:video, organization: org, mux_status: "ready")
      v2 = insert(:video, organization: org, mux_status: "ready")

      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :content_row,
          config: %{
            "title" => "Recent",
            "source_type" => "recent",
            "max_items" => 5
          }
        })

      resolved = LandingPage.resolve_landing_section(org, section)
      ids = resolved.config["items"] |> Enum.map(& &1.id)
      assert v1.id in ids
      assert v2.id in ids
    end

    test "content_row resolves collection items", %{scope: scope, org: org} do
      collection = insert(:collection, organization: org)
      video = insert(:video, organization: org)

      _ =
        insert(:collection_item,
          organization: org,
          collection: collection,
          video: video,
          item_type: :video,
          position: 0
        )

      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :content_row,
          config: %{
            "title" => "Coll",
            "source_type" => "collection",
            "source_id" => collection.id,
            "max_items" => 5
          }
        })

      resolved = LandingPage.resolve_landing_section(org, section)
      assert length(resolved.config["items"]) == 1
    end

    test "plan_display injects active plans", %{scope: scope, org: org} do
      _inactive = insert(:plan, organization: org, active: false, name: "Old")
      active = insert(:plan, organization: org, active: true, name: "Pro")

      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :plan_display,
          config: %{"headline" => "Plans"}
        })

      resolved = LandingPage.resolve_landing_section(org, section)
      plan_names = Enum.map(resolved.config["plans"], & &1.name)
      assert "Pro" in plan_names
      assert active.name in plan_names
      refute "Old" in plan_names
    end

    test "hero_slider with use_existing_hero loads slides", %{scope: scope, org: org} do
      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :hero_slider,
          config: %{"use_existing_hero" => true}
        })

      resolved = LandingPage.resolve_landing_section(org, section)
      # No hero row exists, so slides should be empty but key present
      assert Map.has_key?(resolved.config, "slides")
      assert resolved.config["slides"] == []
    end

    test "hero_slider without use_existing_hero is unchanged", %{scope: scope, org: org} do
      {:ok, section} =
        LandingPage.create_landing_section(scope, %{
          section_type: :hero_slider,
          config: %{"use_existing_hero" => false}
        })

      resolved = LandingPage.resolve_landing_section(org, section)
      refute Map.has_key?(resolved.config, "slides")
    end
  end

  describe "seed_default_landing_page/1" do
    test "creates the default sections in order", %{scope: scope, org: org} do
      assert :ok = LandingPage.seed_default_landing_page(scope)

      sections = LandingPage.list_landing_sections_admin(org)
      assert length(sections) == 5
      assert Enum.all?(sections, & &1.visible)

      types = Enum.map(sections, & &1.section_type)
      assert types == [:marketing_copy, :header_text, :content_row, :plan_display, :faq]

      [hero | _] = sections
      assert hero.config["headline"] =~ org.name
    end

    test "is a no-op if sections already exist", %{scope: scope} do
      {:ok, _} =
        LandingPage.create_landing_section(scope, %{
          section_type: :header_text,
          config: %{"headline" => "X"}
        })

      assert {:error, :already_seeded} = LandingPage.seed_default_landing_page(scope)
    end
  end
end
