defmodule MarqueeFeatures.Steps.DemoShorts do
  use Cucumberex.DSL
  import ExUnit.Assertions
  alias Marquee.{AdminDemo, Content, DemoSeeder, DemoShorts, Repo}

  when_("a Workshop demo is provisioned with reviewed portrait Shorts", fn world ->
    previous =
      for key <- [:demo_shorts_catalog, :subscriber_demo_catalog],
          do: {key, Application.fetch_env(:marquee, key)}

    clips =
      Enum.map(
        Marquee.SubscriberDemoFixtures.catalog_manifest(),
        &Map.merge(&1, %{
          slug: "short-" <> &1.slug,
          mux_asset_id: "portrait-" <> &1.mux_asset_id,
          mux_playback_id: "portrait-" <> &1.mux_playback_id,
          aspect_ratio: "9:16",
          duration: 20.0,
          creator_name: "Portrait fixture creator",
          creator_url: "https://media.example.test/portrait-creator",
          license_url: "https://media.example.test/license"
        })
      )

    Application.put_env(:marquee, :demo_shorts_catalog, %{workshop: clips})

    Application.put_env(
      :marquee,
      :subscriber_demo_catalog,
      Marquee.SubscriberDemoFixtures.catalog_manifest()
    )

    try do
      assert {:ok, catalog} = DemoSeeder.seed_subscriber_demo()
      Map.put(world, :shorts_catalog, catalog)
    after
      restore(previous)
    end
  end)

  then_("the demo Shorts are curated separately from the longform episodes", fn world ->
    catalog = world.shorts_catalog
    items = Content.list_short_feed_items(catalog.organization).results
    assert catalog.organization.shorts_feed_enabled
    assert length(items) == 3
    assert length(catalog.videos) == 3
    assert Enum.all?(items, &(&1.video.aspect_ratio == "9:16"))

    assert Enum.all?(
             items,
             &(&1.video_id in catalog.organization.features["subscriber_demo_video_ids"])
           )

    refute Enum.any?(items, &(&1.video_id in Enum.map(catalog.videos, fn video -> video.id end)))
    world
  end)

  when_("an operator disables and curates a provisioned demo Shorts feed", fn world ->
    org = Marquee.Factory.insert(:organization)

    video =
      Marquee.Factory.insert(:video, organization: org, aspect_ratio: "9:16", duration: 20.0)

    assert {:ok, org} = DemoShorts.seed(org, [video])
    [item] = Content.list_short_feed_items(org).results
    Repo.delete!(item)
    org = Repo.update!(Ecto.Changeset.change(org, shorts_feed_enabled: false))
    Map.merge(world, %{shorts_org: org, shorts_video: video})
  end)

  then_("provisioning again preserves the disabled setting and curated feed", fn world ->
    assert {:ok, org} = DemoShorts.seed(world.shorts_org, [world.shorts_video])
    refute org.shorts_feed_enabled
    assert Content.list_short_feed_items(org).results == []
    world
  end)

  when_("a private demo visitor curates Shorts and opens viewer preview", fn world ->
    import Wallaby.Browser
    import Wallaby.Query
    import MarqueeFeatures.Support.Browser
    host = URI.parse(MarqueeWeb.Endpoint.url()).host
    travel = Marquee.AdminDemoFixtures.catalog_manifest()

    clip =
      hd(travel.clips)
      |> Map.merge(%{slug: "portrait-sample", aspect_ratio: "9:16", duration: 20.0})

    path = Path.join(System.tmp_dir!(), "demo-shorts-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(travel))

    changes = [
      admin_demo: [enabled: true, host: host, catalog_path: path],
      demo_shorts_catalog: %{travel: [clip]}
    ]

    previous = for {key, _} <- changes, do: {key, Application.fetch_env(:marquee, key)}
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    try do
      {:ok, _} = AdminDemo.configure_host(host)

      session =
        world.session
        |> visit("/demo/admin")
        |> click(css("[data-test=admin-demo-start]"))
        |> assert_has(css("[data-test=admin-demo-bar]"))
        |> visit_live("/admin/shorts")
        |> assert_has(css(~s([data-test="shorts-enabled-toggle"][aria-checked="true"])))
        |> click(css("[data-test=shorts-enabled-toggle]"))
        |> assert_has(css(~s([data-test="shorts-enabled-toggle"][aria-checked="false"])))
        |> click(css("[data-test=shorts-enabled-toggle]"))
        |> assert_has(css(~s([data-test="shorts-enabled-toggle"][aria-checked="true"])))
        |> visit_live("/shorts")

      Map.put(world, :session, session)
      |> Map.put(:portrait_playback, clip.mux_playback_id)
    after
      File.rm(path)
      restore(previous)
    end
  end)

  then_("the private viewer preview exposes the approved portrait playback", fn world ->
    import Wallaby.Browser
    import Wallaby.Query

    assert_has(
      world.session,
      css(~s(article[data-playback-id="#{world.portrait_playback}"][data-orientation="portrait"]))
    )

    world
  end)

  defp restore(previous) do
    for {key, value} <- previous do
      case value do
        {:ok, value} -> Application.put_env(:marquee, key, value)
        :error -> Application.delete_env(:marquee, key)
      end
    end
  end
end
