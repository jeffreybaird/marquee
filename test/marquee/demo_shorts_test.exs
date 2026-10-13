defmodule Marquee.DemoShortsTest do
  use Marquee.DataCase, async: false

  alias Marquee.Accounts.Organization
  alias Marquee.{Content, DemoSeeder, DemoShorts}

  test "feed provisioning selects ready tenant portrait footage and preserves curation on repeat" do
    org = insert(:organization)
    portrait = insert(:video, organization: org, aspect_ratio: "9:16", duration: 20.0)
    other = insert(:video, organization: org, aspect_ratio: "9:16", duration: 30.0)

    rejected = [
      insert(:video, aspect_ratio: "9:16", duration: 20.0),
      insert(:video, organization: org, aspect_ratio: "16:9", duration: 20.0),
      insert(:video, organization: org, aspect_ratio: nil, duration: 20.0),
      insert(:video, organization: org, aspect_ratio: "9:16", duration: 181.0),
      insert(:video, organization: org, aspect_ratio: "9:16", duration: 0.0),
      insert(:video,
        organization: org,
        aspect_ratio: "9:16",
        duration: 20.0,
        mux_status: "preparing"
      ),
      insert(:video,
        organization: org,
        aspect_ratio: "9:16",
        duration: 20.0,
        deleted_at: DateTime.utc_now(:second)
      )
    ]

    assert {:ok, seeded} = DemoShorts.seed(org, [portrait, other | rejected])
    assert seeded.shorts_feed_enabled
    assert seeded.shorts_feed_access == "subscribers_only"

    assert Enum.map(Content.list_short_feed_items(seeded).results, & &1.video_id) == [
             portrait.id,
             other.id
           ]

    [first, second] = Content.list_short_feed_items(seeded).results
    Repo.delete!(first)
    Repo.update!(Ecto.Changeset.change(second, position: 12))

    Repo.update!(
      Ecto.Changeset.change(seeded, shorts_feed_enabled: false, shorts_feed_access: "public")
    )

    assert {:ok, repeated} = DemoShorts.seed(org, [portrait, other | rejected])
    refute repeated.shorts_feed_enabled
    assert repeated.shorts_feed_access == "public"
    assert [%{id: id, position: 12}] = Content.list_short_feed_items(repeated).results
    assert id == second.id
    assert Repo.get!(Organization, org.id).features["demo_shorts_seeded"]
  end

  test "empty or ineligible inputs do not advertise an empty enabled demo feed" do
    org = insert(:organization)
    landscape = insert(:video, organization: org, aspect_ratio: "16:9", duration: 20.0)
    assert {:ok, unchanged} = DemoShorts.seed(org, [landscape])
    refute unchanged.shorts_feed_enabled
    assert Content.list_short_feed_items(org).results == []
    portrait = insert(:video, organization: org, aspect_ratio: "9:16", duration: 20.0)
    assert {:ok, seeded} = DemoShorts.seed(unchanged, [portrait])
    assert seeded.shorts_feed_enabled
    assert [%{video_id: id}] = Content.list_short_feed_items(seeded).results
    assert id == portrait.id
  end

  test "a landscape or missing-playback manifest fails before creating videos" do
    prior = Application.fetch_env(:marquee, :demo_shorts_catalog)

    on_exit(fn ->
      case prior do
        {:ok, value} -> Application.put_env(:marquee, :demo_shorts_catalog, value)
        :error -> Application.delete_env(:marquee, :demo_shorts_catalog)
      end
    end)

    org = insert(:organization)
    clip = hd(Marquee.AdminDemoFixtures.catalog_manifest().clips)

    for invalid <- [
          Map.put(clip, :aspect_ratio, "16:9"),
          Map.merge(clip, %{aspect_ratio: "9:16", mux_playback_id: ""})
        ] do
      Application.put_env(:marquee, :demo_shorts_catalog, %{travel: [invalid]})
      assert {:error, :media_not_configured} = DemoShorts.seed_catalog(org, :travel)
      refute Repo.exists?(from v in Marquee.Content.Video, where: v.organization_id == ^org.id)
      refute Repo.get!(Organization, org.id).shorts_feed_enabled
    end
  end

  test "offline enrichment provisions all five existing demo tenants once and leaves customers alone" do
    prior = Application.fetch_env(:marquee, :demo_shorts_catalog)

    on_exit(fn ->
      case prior do
        {:ok, value} -> Application.put_env(:marquee, :demo_shorts_catalog, value)
        :error -> Application.delete_env(:marquee, :demo_shorts_catalog)
      end
    end)

    clip =
      hd(Marquee.AdminDemoFixtures.catalog_manifest().clips)
      |> Map.merge(%{aspect_ratio: "9:16", duration: 20.0})

    Application.put_env(:marquee, :demo_shorts_catalog, %{travel: [clip], workshop: [clip]})
    orgs = Enum.map(DemoSeeder.org_slugs(), &insert(:organization, slug: &1))
    customer = insert(:organization)
    assert {:ok, seeded} = DemoSeeder.seed_shorts()
    assert Enum.map(seeded, & &1.id) == Enum.map(orgs, & &1.id)

    for org <- seeded do
      assert org.shorts_feed_enabled
      assert [%{video: video}] = Content.list_short_feed_items(org).results
      assert video.organization_id == org.id
      assert video.aspect_ratio == "9:16"
      assert video.mux_asset_id == nil
    end

    before = Enum.map(seeded, &Content.list_short_feed_items(&1).results)
    assert {:ok, repeated} = DemoSeeder.seed_shorts()
    assert Enum.map(repeated, &Content.list_short_feed_items(&1).results) == before
    refute Repo.get!(Organization, customer.id).shorts_feed_enabled
    assert Content.list_short_feed_items(customer).results == []
  end
end
