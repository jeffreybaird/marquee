defmodule Marquee.Catalog.RowCardVariantTest do
  use Marquee.DataCase, async: false

  alias Marquee.Accounts.Scope
  alias Marquee.Catalog
  alias Marquee.Catalog.Row

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{scope: scope}
  end

  describe "compat_row_type/1" do
    test "maps legacy source types onto preset row types" do
      assert Row.compat_row_type(:popular) == :popularity
      assert Row.compat_row_type(:recent) == :popularity
      assert Row.compat_row_type(:curated) == :popularity
      assert Row.compat_row_type(:collection) == :editorial_spotlight
      assert Row.compat_row_type(:tag) == :tags
      assert Row.compat_row_type(:new_seasons) == :series
    end

    test "passes new preset row types through unchanged" do
      for t <- [
            :hero,
            :popularity,
            :tags,
            :preferences,
            :series,
            :continue_watching,
            :creator_showcase,
            :editorial_spotlight
          ] do
        assert Row.compat_row_type(t) == t
      end
    end
  end

  describe "Row.changeset with card_variant" do
    test "accepts a compatible variant", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{
                 title: "Popular",
                 source_type: :popularity,
                 card_variant: "poster_portrait",
                 max_items: 20
               })

      assert row.card_variant == "poster_portrait"
    end

    test "accepts any valid variant in any row type", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{
                 title: "Hero",
                 source_type: :hero,
                 card_variant: "progress_course",
                 max_items: 20
               })

      assert row.card_variant == "progress_course"
    end

    test "rejects an unknown variant", %{scope: scope} do
      assert {:error, :validation, cs} =
               Catalog.create_row(scope, %{
                 title: "X",
                 source_type: :popularity,
                 card_variant: "bogus_card",
                 max_items: 20
               })

      assert "is not a recognized card variant" in errors_on(cs).card_variant
    end

    test "allows blank/nil card_variant (falls back to default)", %{scope: scope} do
      assert {:ok, row} =
               Catalog.create_row(scope, %{
                 title: "Default",
                 source_type: :popularity,
                 max_items: 20
               })

      assert row.card_variant == nil
    end
  end
end
