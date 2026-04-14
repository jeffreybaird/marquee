defmodule Bobine.Catalog.SeedFromPresetTest do
  use Bobine.DataCase, async: false

  alias Bobine.Accounts.Scope
  alias Bobine.Catalog

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{org: org, scope: scope}
  end

  describe "seed_rows_from_preset_if_empty/2" do
    test "seeds rows from a preset when catalog is empty", %{org: org, scope: scope} do
      assert {:ok, :seeded, rows} =
               Catalog.seed_rows_from_preset_if_empty(scope, "catalog_cinema")

      assert length(rows) > 0

      %{results: stored} = Catalog.list_rows(org)
      source_types = stored |> Enum.map(& &1.source_type) |> Enum.sort()

      assert :hero in source_types
      assert :continue_watching in source_types

      # Every seeded row has a card_variant and is visible
      Enum.each(stored, fn row ->
        assert row.card_variant != nil
        assert row.visible == true
      end)
    end

    test "skips seeding when catalog already has rows", %{org: org, scope: scope} do
      {:ok, _} =
        Catalog.create_row(scope, %{
          title: "Existing",
          source_type: :curated,
          max_items: 20
        })

      assert {:ok, :skipped} =
               Catalog.seed_rows_from_preset_if_empty(scope, "creator_channel")

      %{results: stored} = Catalog.list_rows(org)
      # Only the pre-existing row remains
      assert length(stored) == 1
      assert hd(stored).title == "Existing"
    end

    test "returns :not_found for unknown preset", %{scope: scope} do
      assert {:error, :not_found} =
               Catalog.seed_rows_from_preset_if_empty(scope, "nonsense")
    end
  end
end
