defmodule MarqueeFeatures.Steps.SubscriberDemo do
  @moduledoc "Context acceptance steps for isolated Workshop subscriber sessions."
  use Cucumberex.DSL
  import Marquee.Factory
  import ExUnit.Assertions
  alias Marquee.{Engagement, Repo, SubscriberDemo, Viewers}

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
