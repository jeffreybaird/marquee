defmodule Marquee.Catalog.LayoutTest do
  use Marquee.DataCase, async: true

  alias Marquee.Catalog.Layout

  describe "changeset/2" do
    setup do
      org = insert(:organization)
      %{org: org}
    end

    test "requires preset_name, default_browse_card_variant, and organization_id",
         %{org: _org} do
      cs = Layout.changeset(%Layout{}, %{})
      refute cs.valid?

      for field <- [:preset_name, :default_browse_card_variant, :organization_id] do
        assert Map.has_key?(errors_on(cs), field),
               "expected #{field} to be required"
      end
    end

    test "rejects unknown preset name", %{org: org} do
      attrs = %{
        organization_id: org.id,
        preset_name: "bogus",
        default_browse_card_variant: "poster_portrait"
      }

      cs = Layout.changeset(%Layout{}, attrs)
      refute cs.valid?
      assert Map.has_key?(errors_on(cs), :preset_name)
    end

    test "rejects unknown default browse card variant", %{org: org} do
      attrs = %{
        organization_id: org.id,
        preset_name: "catalog_cinema",
        default_browse_card_variant: "bogus"
      }

      cs = Layout.changeset(%Layout{}, attrs)
      refute cs.valid?
      assert Map.has_key?(errors_on(cs), :default_browse_card_variant)
    end

    test "accepts a valid layout", %{org: org} do
      attrs = %{
        organization_id: org.id,
        preset_name: "catalog_cinema",
        default_browse_card_variant: "poster_portrait"
      }

      cs = Layout.changeset(%Layout{}, attrs)
      assert cs.valid?
    end
  end
end
