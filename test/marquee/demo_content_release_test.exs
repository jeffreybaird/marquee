defmodule Marquee.DemoContentReleaseTest do
  use Marquee.DataCase, async: false

  alias Marquee.Accounts.Organization
  alias Marquee.{Content, DemoSeeder, Release}
  alias Marquee.Content.Video

  setup do
    portraits =
      for n <- 1..2 do
        hd(Marquee.AdminDemoFixtures.catalog_manifest().clips)
        |> Map.merge(%{
          slug: "deploy-portrait-#{n}",
          aspect_ratio: "9:16",
          duration: 20.0,
          mux_asset_id: "deploy-portrait-asset-#{n}",
          mux_playback_id: "deploy-portrait-playback-#{n}"
        })
      end

    changes = [
      demo_shorts_catalog: %{travel: portraits, workshop: portraits},
      subscriber_demo_catalog: Marquee.SubscriberDemoFixtures.catalog_manifest()
    ]

    previous = for {key, _} <- changes, do: {key, Application.fetch_env(:marquee, key)}
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    %{portraits: portraits}
  end

  test "boot seeds missing Shorts for every existing demo and does not create missing tenants or change customers",
       %{portraits: portraits} do
    orgs = Enum.map(DemoSeeder.org_slugs(), &insert(:organization, slug: &1))
    customer = insert(:organization)
    assert {:ok, _} = Release.seed_missing_demo_content()
    assert Repo.aggregate(Organization, :count) == 6

    for org <- orgs do
      org = Repo.get!(Organization, org.id)
      assert org.features["demo_shorts_seeded"]
      assert org.shorts_feed_enabled
      items = Content.list_short_feed_items(org).results
      assert Enum.map(items, & &1.video.slug) == Enum.map(portraits, & &1.slug)
      assert Enum.all?(items, &(&1.video.organization_id == org.id))
    end

    refute Repo.get!(Organization, customer.id).shorts_feed_enabled
    refute Repo.exists?(from v in Video, where: v.organization_id == ^customer.id)
  end

  test "missing demo tenants are never created when the other four already exist" do
    for slug <- Enum.take(DemoSeeder.org_slugs(), 4), do: insert(:organization, slug: slug)
    assert {:ok, _} = Release.seed_missing_demo_content()
    refute Repo.get_by(Organization, slug: "prism-plus")
    assert Repo.aggregate(Organization, :count) == 4
  end

  test "soft-deleted demo organizations remain untouched during deployment" do
    org = insert(:organization, slug: "wanderlust-tv", deleted_at: DateTime.utc_now(:second))
    Application.put_env(:marquee, :demo_shorts_catalog, %{})
    assert {:ok, _} = Release.seed_missing_demo_content()
    refute Repo.exists?(from v in Video, where: v.organization_id == ^org.id)
    refute Repo.get!(Organization, org.id).features["demo_shorts_seeded"]
  end

  test "seeded deployments skip catalog readers despite invalid media and preserve deliberate deletions and settings" do
    org = insert(:organization, slug: "wanderlust-tv")
    assert {:ok, _} = Release.seed_missing_demo_content()
    org = Repo.get!(Organization, org.id)
    [first, last] = Content.list_short_feed_items(org).results
    Repo.delete!(first)
    Repo.update!(Ecto.Changeset.change(last, position: 17))
    Repo.update!(Ecto.Changeset.change(last.video, deleted_at: DateTime.utc_now(:second)))

    Repo.update!(
      Ecto.Changeset.change(org, shorts_feed_enabled: false, shorts_feed_access: "public")
    )

    Application.put_env(:marquee, :demo_shorts_catalog, %{})
    Application.put_env(:marquee, :subscriber_demo_catalog, [])
    assert {:ok, _} = Release.seed_missing_demo_content()
    unchanged = Repo.get!(Organization, org.id)
    refute unchanged.shorts_feed_enabled
    assert unchanged.shorts_feed_access == "public"
    assert [%{id: id, position: 17}] = Content.list_short_feed_items(unchanged).results
    assert id == last.id
    assert Repo.get!(Video, last.video_id).deleted_at
    assert Repo.aggregate(from(v in Video, where: v.organization_id == ^org.id), :count) == 2
  end

  test "partial deployment invokes the missing tenant catalog while respecting already seeded tenants",
       %{portraits: portraits} do
    seeded =
      insert(:organization,
        slug: "wanderlust-tv",
        features: %{"demo_shorts_seeded" => true},
        shorts_feed_enabled: false
      )

    missing = insert(:organization, slug: "zenith-fitness")
    Application.put_env(:marquee, :demo_shorts_catalog, %{})
    assert {:error, :media_not_configured} = Release.seed_missing_demo_content()
    refute Repo.get!(Organization, missing.id).features["demo_shorts_seeded"]
    Application.put_env(:marquee, :demo_shorts_catalog, %{travel: portraits, workshop: portraits})
    assert {:ok, _} = Release.seed_missing_demo_content()
    assert Repo.get!(Organization, missing.id).features["demo_shorts_seeded"]
    assert length(Content.list_short_feed_items(missing).results) == 2
    assert Content.list_short_feed_items(seeded).results == []
    refute Repo.get!(Organization, seeded.id).shorts_feed_enabled
  end

  test "eligible existing Workshop seeds its absent longform catalog once and skips future refreshes" do
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})
    assert {:ok, _} = Release.seed_missing_demo_content()
    org = Repo.get!(Organization, org.id)
    ids = org.features["subscriber_demo_video_ids"]
    assert length(ids) == 5
    original = Repo.get_by!(Video, organization_id: org.id, slug: "workshop-episode-1")

    Repo.update!(
      Ecto.Changeset.change(original,
        title: "Operator edit",
        deleted_at: DateTime.utc_now(:second)
      )
    )

    Application.put_env(:marquee, :subscriber_demo_catalog, [])
    Application.put_env(:marquee, :demo_shorts_catalog, %{})
    assert {:ok, _} = Release.seed_missing_demo_content()
    assert Repo.get!(Organization, org.id).features["subscriber_demo_video_ids"] == ids
    assert Repo.get!(Video, original.id).title == "Operator edit"
    assert Repo.get!(Video, original.id).deleted_at
    assert Repo.aggregate(from(v in Video, where: v.organization_id == ^org.id), :count) == 5
  end

  test "boot does not enable subscriber demo or create Workshop when no eligible tenant exists" do
    assert {:ok, _} = Release.seed_missing_demo_content()
    assert Repo.aggregate(Organization, :count) == 0
    org = insert(:organization, slug: "the-workshop")
    assert {:ok, _} = Release.seed_missing_demo_content()
    refute Repo.get!(Organization, org.id).features["subscriber_demo"]
    refute Repo.get_by(Video, organization_id: org.id, slug: "workshop-episode-1")
  end

  test "an intentionally emptied Workshop allowlist remains initialized and is never reseeded" do
    org =
      insert(:organization,
        slug: "the-workshop",
        features: %{
          "subscriber_demo" => true,
          "subscriber_demo_video_ids" => [],
          "demo_shorts_seeded" => true
        }
      )

    Application.put_env(:marquee, :subscriber_demo_catalog, [])
    Application.put_env(:marquee, :demo_shorts_catalog, %{})
    assert {:ok, _} = Release.seed_missing_demo_content()
    assert Repo.get!(Organization, org.id).features["subscriber_demo_video_ids"] == []
    refute Repo.exists?(from v in Video, where: v.organization_id == ^org.id)
  end

  test "legacy Workshop series without an allowlist is preserved rather than refreshed" do
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})

    series =
      insert(:series,
        organization: org,
        slug: "inside-the-workshop",
        title: "Operator's existing series"
      )

    edited =
      insert(:video,
        organization: org,
        slug: "workshop-episode-1",
        title: "Operator's existing episode",
        deleted_at: DateTime.utc_now(:second)
      )

    Application.put_env(:marquee, :subscriber_demo_catalog, [])
    assert {:ok, _} = Release.seed_missing_demo_content()
    assert Repo.get!(series.__struct__, series.id).title == "Operator's existing series"
    assert Repo.get!(Video, edited.id).title == "Operator's existing episode"
    assert Repo.get!(Video, edited.id).deleted_at
    refute Repo.get_by(Video, organization_id: org.id, slug: "workshop-episode-2")
  end
end
