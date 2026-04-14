defmodule Bobine.Catalog.LayoutTest do
  use Bobine.DataCase, async: true

  alias Bobine.Catalog
  alias Bobine.Catalog.Layout

  describe "changeset/2" do
    setup do
      org = insert(:organization)
      %{org: org}
    end

    test "rejects fewer than 2 rows", %{org: org} do
      attrs = %{
        organization_id: org.id,
        preset_name: "catalog_cinema",
        default_browse_card_variant: "poster_portrait",
        rows: [%{row_type: :continue_watching, card_variant: :landscape_episode, position: 0}]
      }

      cs = Layout.changeset(%Layout{}, attrs)
      refute cs.valid?
      assert "must contain at least 2 rows" in errors_on(cs).rows
    end

    test "rejects missing continue_watching row", %{org: org} do
      attrs = %{
        organization_id: org.id,
        preset_name: "catalog_cinema",
        default_browse_card_variant: "poster_portrait",
        rows: [
          %{row_type: :hero, card_variant: :poster_portrait, position: 0},
          %{row_type: :popularity, card_variant: :poster_portrait, position: 1}
        ]
      }

      cs = Layout.changeset(%Layout{}, attrs)
      refute cs.valid?

      assert "continue_watching row cannot be removed — only hidden" in errors_on(cs).rows
    end

    test "rejects incompatible card/row combination", %{org: org} do
      attrs = %{
        organization_id: org.id,
        preset_name: "catalog_cinema",
        default_browse_card_variant: "poster_portrait",
        rows: [
          %{row_type: :hero, card_variant: :progress_course, position: 0},
          %{row_type: :continue_watching, card_variant: :landscape_episode, position: 1}
        ]
      }

      cs = Layout.changeset(%Layout{}, attrs)
      refute cs.valid?

      assert Enum.any?(
               errors_on(cs).rows,
               &String.contains?(&1, "not a compatible card variant")
             )
    end

    test "rejects unknown preset name", %{org: org} do
      attrs = %{
        organization_id: org.id,
        preset_name: "bogus",
        default_browse_card_variant: "poster_portrait",
        rows: [
          %{row_type: :continue_watching, card_variant: :landscape_episode, position: 0},
          %{row_type: :popularity, card_variant: :poster_portrait, position: 1}
        ]
      }

      cs = Layout.changeset(%Layout{}, attrs)
      refute cs.valid?
      assert Map.has_key?(errors_on(cs), :preset_name)
    end

    test "accepts a valid layout", %{org: org} do
      {:ok, preset} = Catalog.Presets.get("catalog_cinema")

      attrs = %{
        organization_id: org.id,
        preset_name: preset.name,
        default_browse_card_variant: Atom.to_string(preset.default_browse_card_variant),
        rows: preset.rows
      }

      cs = Layout.changeset(%Layout{}, attrs)
      assert cs.valid?
    end
  end
end
