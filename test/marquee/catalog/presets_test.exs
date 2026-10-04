defmodule Marquee.Catalog.PresetsTest do
  use ExUnit.Case, async: true
  alias Marquee.Catalog.Presets

  describe "get/1" do
    test "returns each known preset" do
      for name <- ~w(catalog_cinema learning_platform creator_channel) do
        assert {:ok, preset} = Presets.get(name)
        assert preset.name == name
        assert is_binary(preset.display_font)
        assert length(preset.rows) >= 2
      end
    end

    test "returns :not_found for unknown names" do
      assert Presets.get("nope") == {:error, :not_found}
      assert Presets.get(:catalog_cinema) == {:error, :not_found}
    end
  end

  describe "list/0 and names/0" do
    test "list enumerates all presets sorted by name" do
      names = Enum.map(Presets.list(), & &1.name)
      assert names == Presets.names()
      assert names == Enum.sort(names)
    end
  end

  describe "compatible?/2 — matrix from .claude/brand-system.md" do
    test "poster_portrait allowed in hero" do
      assert Presets.compatible?(:poster_portrait, :hero)
    end

    test "all card variants allowed in all row types" do
      for variant <- Presets.card_variants(),
          row_type <- Presets.row_types() do
        assert Presets.compatible?(variant, row_type),
               "#{variant} should be compatible with #{row_type}"
      end
    end

    test "unknown atoms return false" do
      refute Presets.compatible?(:bogus, :hero)
      refute Presets.compatible?(:poster_portrait, :bogus)
    end
  end

  describe "variants_for_row/1" do
    test "every row type accepts all card variants" do
      for row_type <- Presets.row_types() do
        variants = Presets.variants_for_row(row_type)
        assert variants == Presets.card_variants()
      end
    end

    test "returns [] for unknown row type" do
      assert Presets.variants_for_row(:unknown) == []
    end
  end

  describe "preset row compatibility" do
    test "every preset's rows satisfy the compatibility matrix" do
      for preset <- Presets.list(),
          row <- preset.rows do
        assert Presets.compatible?(row.card_variant, row.row_type),
               "preset #{preset.name}: #{row.card_variant} invalid in #{row.row_type}"
      end
    end

    test "every preset includes a continue_watching row" do
      for preset <- Presets.list() do
        assert Enum.any?(preset.rows, &(&1.row_type == :continue_watching)),
               "preset #{preset.name} missing continue_watching row"
      end
    end
  end
end
