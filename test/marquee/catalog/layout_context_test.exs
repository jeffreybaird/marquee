defmodule Marquee.Catalog.LayoutContextTest do
  use Marquee.DataCase, async: true

  alias Marquee.Catalog

  setup do
    org = insert(:organization)
    %{org: org}
  end

  describe "get_or_create_layout/1" do
    test "creates a layout from catalog_cinema when org has no preset", %{org: org} do
      assert {:ok, layout} = Catalog.get_or_create_layout(org)
      assert layout.preset_name == "catalog_cinema"
      assert layout.organization_id == org.id
      assert layout.default_browse_card_variant == "poster_portrait"
    end

    test "returns existing layout on second call", %{org: org} do
      {:ok, layout1} = Catalog.get_or_create_layout(org)
      {:ok, layout2} = Catalog.get_or_create_layout(org)
      assert layout1.id == layout2.id
    end

    test "seeds from org.preset_name when set", %{org: org} do
      {:ok, org} =
        Marquee.Accounts.update_organization_branding(org, %{
          preset_name: "learning_platform",
          display_font: "DM Serif Display",
          accent_color_base: "oklch(0.62 0.18 250)",
          accent_color_hover: "oklch(0.68 0.18 250)",
          accent_color_active: "oklch(0.56 0.18 250)",
          accent_color_subtle: "oklch(0.26 0.08 250)"
        })

      {:ok, layout} = Catalog.get_or_create_layout(org)
      assert layout.preset_name == "learning_platform"
    end
  end

  describe "update_layout/2" do
    test "broadcasts {:layout_updated, layout} on the layout topic", %{org: org} do
      {:ok, layout} = Catalog.get_or_create_layout(org)
      Catalog.subscribe_to_layout(org)

      assert {:ok, updated} =
               Catalog.update_layout(layout, %{default_browse_card_variant: "landscape_episode"})

      assert updated.default_browse_card_variant == "landscape_episode"
      assert_receive {:layout_updated, ^updated}
    end

    test "returns validation error for unknown browse card variant", %{org: org} do
      {:ok, layout} = Catalog.get_or_create_layout(org)

      assert {:error, :validation, cs} =
               Catalog.update_layout(layout, %{default_browse_card_variant: "bogus"})

      refute cs.valid?
    end
  end

  describe "reset_layout_to_preset/2" do
    test "records the preset_name and broadcasts", %{org: org} do
      {:ok, _} = Catalog.get_or_create_layout(org)
      Catalog.subscribe_to_layout(org)

      assert {:ok, layout} = Catalog.reset_layout_to_preset(org, "creator_channel")
      assert layout.preset_name == "creator_channel"
      assert_receive {:layout_updated, ^layout}
    end

    test "returns :not_found for unknown preset", %{org: org} do
      assert Catalog.reset_layout_to_preset(org, "bogus") == {:error, :not_found}
    end
  end

  describe "layout_topic/1" do
    test "derives a stable topic name for the org", %{org: org} do
      assert Catalog.layout_topic(org) == "layout:#{org.id}"
      assert Catalog.layout_topic(org.id) == "layout:#{org.id}"
    end
  end
end
