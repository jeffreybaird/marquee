defmodule Marquee.SubscriberDemoCatalogExpansionTest do
  use Marquee.DataCase, async: false

  alias Marquee.Accounts.Organization
  alias Marquee.Catalog.Row
  alias Marquee.Content.{CollectionItem, Episode}
  alias Marquee.SubscriberDemo

  setup do
    previous = Application.fetch_env(:marquee, :subscriber_demo_catalog)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:marquee, :subscriber_demo_catalog, value)
        :error -> Application.delete_env(:marquee, :subscriber_demo_catalog)
      end
    end)

    %{org: insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})}
  end

  test "expanding to eighteen clips preserves existing episodes and supplies three scrollable rows",
       %{org: org} do
    initial = seed!(org, manifest(3))
    original_ids = Enum.map(initial.videos, & &1.id)

    original_episodes =
      Repo.all(
        from e in Episode,
          where: e.organization_id == ^org.id,
          order_by: e.episode_number,
          select: {e.id, e.video_id, e.episode_number}
      )

    expanded = seed!(org, manifest(18))
    assert length(expanded.videos) == 18
    assert expanded.series.id == initial.series.id

    assert Repo.all(
             from e in Episode,
               where: e.organization_id == ^org.id,
               order_by: e.episode_number,
               select: e.video_id
           ) == Enum.map(expanded.videos, & &1.id)

    assert Enum.take(Enum.map(expanded.videos, & &1.id), 3) == original_ids

    assert Repo.all(
             from e in Episode,
               where: e.organization_id == ^org.id and e.video_id in ^original_ids,
               order_by: e.episode_number,
               select: {e.id, e.video_id, e.episode_number}
           ) == original_episodes

    assert length(expanded.collections) == 3
    assert_collection_memberships(org, expanded)
    assert_demo_rows(org, expanded)
    again = seed!(org, manifest(18))
    assert again.series.id == expanded.series.id
    assert Enum.map(again.videos, & &1.id) == Enum.map(expanded.videos, & &1.id)
    assert Enum.map(again.collections, & &1.id) == Enum.map(expanded.collections, & &1.id)
    assert_collection_memberships(org, again)
    assert_demo_rows(org, again)
  end

  test "reseeding reconciles collection order and removes obsolete memberships", %{org: org} do
    legacy = insert(:video, organization: org, title: "Unrelated operator content")
    legacy_row = insert(:row, organization: org, title: "Unrelated operator row", visible: true)
    expanded = seed!(org, manifest(18))
    reordered_manifest = Enum.take(manifest(18), 3) ++ Enum.reverse(Enum.drop(manifest(18), 3))
    reordered = seed!(org, reordered_manifest)
    assert Enum.map(reordered.collections, & &1.id) == Enum.map(expanded.collections, & &1.id)
    assert_collection_memberships(org, reordered)
    smaller = seed!(org, Enum.take(reordered_manifest, 12))
    assert_collection_memberships(org, smaller)
    assert_demo_rows(org, smaller)
    desired_ids = Enum.map(smaller.videos, & &1.id)
    collection_ids = Enum.map(smaller.collections, & &1.id)

    refute Repo.exists?(
             from i in CollectionItem,
               where:
                 i.organization_id == ^org.id and i.collection_id in ^collection_ids and
                   i.video_id not in ^desired_ids
           )

    assert Repo.get!(Marquee.Content.Video, legacy.id).deleted_at == nil
    assert Repo.get!(Row, legacy_row.id).visible
  end

  test "manifest accepts the bounded twenty-four clip maximum and rejects twenty-five", %{
    org: org
  } do
    assert length(seed!(org, manifest(24)).videos) == 24
    Application.put_env(:marquee, :subscriber_demo_catalog, manifest(25))
    assert {:error, :media_not_configured} = SubscriberDemo.seed_catalog(org)
  end

  defp assert_collection_memberships(org, catalog) do
    ids = Enum.map(catalog.videos, & &1.id)
    count = length(ids)

    for {collection, offset} <-
          Enum.zip(catalog.collections, [0, div(count, 3), div(2 * count, 3)]) do
      items =
        Repo.all(
          from i in CollectionItem,
            where: i.organization_id == ^org.id and i.collection_id == ^collection.id,
            order_by: i.position
        )

      expected = Enum.take(Enum.drop(ids, offset) ++ Enum.take(ids, offset), 12)
      assert Enum.map(items, & &1.video_id) == expected
      assert Enum.map(items, & &1.position) == Enum.to_list(0..(length(expected) - 1))
      assert length(Enum.uniq_by(items, & &1.video_id)) == length(items)
    end
  end

  defp assert_demo_rows(org, catalog) do
    stored = Repo.get!(Organization, org.id)
    row_ids = stored.features["subscriber_demo_row_ids"]
    rows = Repo.all(from r in Row, where: r.organization_id == ^org.id and r.id in ^row_ids)
    assert length(row_ids) == 5
    assert length(rows) == 5
    collection_rows = Enum.filter(rows, &(&1.source_type == :collection))
    assert MapSet.new(collection_rows, & &1.source_id) == MapSet.new(catalog.collections, & &1.id)
    assert Enum.all?(collection_rows, &(&1.max_items == 12 and &1.visible))

    assert Enum.sort(Enum.map(rows, & &1.source_type)) ==
             Enum.sort([
               :hero,
               :continue_watching,
               :collection,
               :collection,
               :collection
             ])
  end

  defp seed!(org, entries) do
    Application.put_env(:marquee, :subscriber_demo_catalog, entries)
    assert {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    catalog
  end

  defp manifest(count) do
    for n <- 1..count do
      %{
        slug: "workshop-episode-#{n}",
        title: "Woodwork study #{n}",
        description: "Observed woodwork operation #{n}.",
        mux_asset_id: "fixture-asset-#{n}",
        mux_playback_id: "fixture-playback-#{n}",
        duration: 180.0,
        source_url: "https://example.com/woodwork-#{n}"
      }
    end
  end
end
