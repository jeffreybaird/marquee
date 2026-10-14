defmodule MarqueeFeatures.Steps.SubscriberDemo do
  @moduledoc "Context acceptance steps for isolated Workshop subscriber sessions."
  use Cucumberex.DSL
  require Wallaby.Browser
  import Wallaby.Browser, only: [execute_query: 2]
  import Marquee.Factory
  import ExUnit.Assertions
  alias Marquee.{Engagement, Repo, SubscriberDemo, Viewers}
  import Ecto.Query

  when_("a fresh browser opens the Workshop homepage", fn world ->
    session = Wallaby.Browser.visit(world.session, "/?org=#{world.demo_org.slug}")
    Map.put(world, :session, session)
  end)

  when_("the visitor chooses Begin demo from the themed landing page", fn world ->
    import Wallaby.Browser, only: [assert_has: 2, execute_query: 2, click: 2]
    assert_has(world.session, Wallaby.Query.css("[data-test=subscriber-demo-landing]"))

    assert_has(
      world.session,
      Wallaby.Query.css("[data-test=subscriber-demo-entry]", text: "Begin demo")
    )

    org_id = world.demo_org.id
    refute Repo.exists?(from v in Marquee.Viewers.Viewer, where: v.organization_id == ^org_id)

    Map.put(
      world,
      :session,
      click(world.session, Wallaby.Query.css("[data-test=subscriber-demo-entry]"))
    )
  end)

  then_("the Workshop catalog opens with a private demo session", fn world ->
    import Wallaby.Browser, only: [assert_has: 2, execute_query: 2]
    assert_has(world.session, Wallaby.Query.css("[data-test=subscriber-demo-banner]"))
    assert_has(world.session, Wallaby.Query.css("[data-test=hero-primary-cta-0]"))
    org_id = world.demo_org.id
    [viewer] = Repo.all(from(v in Marquee.Viewers.Viewer, where: v.organization_id == ^org_id))
    assert SubscriberDemo.demo_viewer?(viewer)
    refute SubscriberDemo.expired?(viewer)
    world
  end)

  then_("the Workshop hero offers three distinct featured videos", fn world ->
    org_id = world.demo_org.id

    video_ids =
      Repo.all(
        from s in Marquee.Catalog.HeroSlide,
          where: s.organization_id == ^org_id and is_nil(s.deleted_at),
          select: s.video_id
      )

    assert length(Enum.uniq(video_ids)) >= 3
    world
  end)

  when_("the visitor dismisses the subscriber demo notice on a narrow screen", fn world ->
    session =
      world.session
      |> Wallaby.Browser.resize_window(390, 844)
      |> Wallaby.Browser.click(Wallaby.Query.css("[data-test=subscriber-demo-dismiss]"))
      |> Wallaby.Browser.assert_has(
        Wallaby.Query.css("[data-test=subscriber-demo-banner]", count: 0)
      )

    Map.put(world, :session, session)
  end)

  then_("the subscriber notice stays hidden through mobile navigation and reload", fn world ->
    import Wallaby.Browser
    import Wallaby.Query, only: [css: 1, css: 2]
    org_id = world.demo_org.id
    [viewer] = Repo.all(from(v in Marquee.Viewers.Viewer, where: v.organization_id == ^org_id))
    {:ok, saved} = Engagement.add_to_watchlist(world.demo_org, viewer, world.demo_video)

    session =
      world.session
      |> click(css("[data-test=subscriber-demo-mobile-nav] a[href='/browse']"))
      |> assert_has(css("[data-test=subscriber-demo-banner]", count: 0))
      |> click(css("[data-test=subscriber-demo-mobile-nav] a[href='/watchlist']"))
      |> assert_has(css("[data-test=sv-watchlist-remove-#{saved.video_id}]"))
      |> visit("/?org=#{world.demo_org.slug}")
      |> assert_has(css("[data-test=hero-primary-cta-0]"))
      |> assert_has(css("[data-test=subscriber-demo-banner]", count: 0))

    assert SubscriberDemo.demo_viewer?(Repo.get!(Marquee.Viewers.Viewer, viewer.id))
    Map.put(world, :session, session)
  end)

  then_("a fresh browser still sees the subscriber demo notice", fn world ->
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Repo, self())
    {:ok, fresh} = Wallaby.start_session(metadata: metadata)

    try do
      fresh
      |> Wallaby.Browser.visit("/?org=#{world.demo_org.slug}")
      |> Wallaby.Browser.click(Wallaby.Query.css("[data-test=subscriber-demo-entry]"))
      |> Wallaby.Browser.assert_has(Wallaby.Query.css("[data-test=subscriber-demo-banner]"))
    after
      Wallaby.end_session(fresh)
    end

    world
  end)

  then_("the Workshop catalog has no managed subscriber explanation row", fn world ->
    org_id = world.demo_org.id

    refute Repo.exists?(
             from r in Marquee.Catalog.Row,
               where:
                 r.organization_id == ^org_id and r.title == "Your subscriber demo" and
                   is_nil(r.deleted_at)
           )

    world
  end)

  given_("The Workshop subscriber demo has a playable catalog", fn world ->
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})
    previous = Application.fetch_env(:marquee, :subscriber_demo_catalog)

    Application.put_env(
      :marquee,
      :subscriber_demo_catalog,
      Marquee.SubscriberDemoFixtures.catalog_manifest()
    )

    catalog =
      try do
        {:ok, catalog} = SubscriberDemo.seed_catalog(org)
        catalog
      after
        case previous do
          {:ok, value} -> Application.put_env(:marquee, :subscriber_demo_catalog, value)
          :error -> Application.delete_env(:marquee, :subscriber_demo_catalog)
        end
      end

    Map.merge(world, %{demo_org: org, demo_video: List.last(catalog.videos)})
  end)

  when_("two visitors start the subscriber demo", fn world ->
    {:ok, first} = SubscriberDemo.start_session(world.demo_org)
    {:ok, second} = SubscriberDemo.start_session(world.demo_org)
    assert first.viewer.id != second.viewer.id
    Map.merge(world, %{demo_first: first, demo_second: second})
  end)

  when_("the first demo visitor saves an episode and watches part of it", fn world ->
    {:ok, _} =
      Engagement.add_to_watchlist(world.demo_org, world.demo_first.viewer, world.demo_video)

    :ok =
      Engagement.update_progress(
        world.demo_org,
        world.demo_first.viewer,
        world.demo_video.id,
        12,
        world.demo_video.duration
      )

    world
  end)

  then_("the first demo visitor can resume that episode", fn world ->
    assert Engagement.get_progress(world.demo_org, world.demo_first.viewer, world.demo_video).position ==
             12

    assert Engagement.in_watchlist?(world.demo_org, world.demo_first.viewer, world.demo_video)
    world
  end)

  then_("the second demo visitor has independent activity", fn world ->
    refute Engagement.in_watchlist?(world.demo_org, world.demo_second.viewer, world.demo_video)
    world
  end)

  when_("the first demo visitor session expires", fn world ->
    viewer = world.demo_first.viewer
    expiry = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601()

    viewer
    |> Ecto.Changeset.change(
      metadata: Map.put(viewer.metadata, "subscriber_demo_expires_at", expiry)
    )
    |> Repo.update!()

    world
  end)

  then_("that demo session no longer authenticates", fn world ->
    assert is_nil(Viewers.get_viewer_by_session_token(world.demo_first.token))
    world
  end)

  then_("expired demo activity can be removed without removing the second visitor", fn world ->
    assert {:ok, 1} = SubscriberDemo.cleanup_expired(world.demo_org, now: DateTime.utc_now())
    assert is_nil(Viewers.get_viewer_by_session_token(world.demo_first.token))

    assert Viewers.get_viewer_by_session_token(world.demo_second.token).id ==
             world.demo_second.viewer.id

    world
  end)
end
