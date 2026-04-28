defmodule BobineFeatures.Steps.Podcasts do
  @moduledoc """
  Acceptance steps for premium podcast shows. Drives the public
  Bobine.Podcasts API rather than the operator UI — the operator and
  subscriber LiveViews are exercised separately by the
  podcasts_live_test.exs / Wallaby suites. Keeping the cucumber surface
  context-level lets it run inside the no-server `mix bobine.cucumber`
  pipeline.
  """

  use Cucumberex.DSL

  import Bobine.Factory
  import ExUnit.Assertions

  alias Bobine.Accounts.Scope
  alias Bobine.Podcasts
  alias Bobine.Podcasts.{Episode, FeedToken}
  alias Bobine.Repo

  # ---- Operator setup -----------------------------------------------------

  given_ "a paid plan exists in the organization", fn world ->
    plan = insert(:plan, organization: world.org)
    Map.put(world, :plan, plan)
  end

  # ---- Show creation ------------------------------------------------------

  when_ "I create a podcast show with a slug and the any-active access mode", fn world ->
    {:ok, show} =
      Podcasts.create_show(world.scope, %{
        title: "Operator Show",
        slug: "operator-show-#{System.unique_integer([:positive])}",
        source_type: "direct_upload",
        access_mode: "any_active",
        owner_email: "owner@example.com"
      })

    Map.put(world, :show, show)
  end

  then_ "the show appears in the operator's podcasts list", fn world ->
    %{results: shows} = Podcasts.list_shows(world.org, per_page: 100)
    assert Enum.any?(shows, &(&1.id == world.show.id))
    world
  end

  then_ "the show is org-scoped to my organization", fn world ->
    assert world.show.organization_id == world.org.id
    world
  end

  # ---- Tier-gated access --------------------------------------------------

  when_ "I create a podcast show that allows only that plan's subscribers", fn world ->
    {:ok, show} =
      Podcasts.create_show(world.scope, %{
        title: "Tier Show",
        slug: "tier-show-#{System.unique_integer([:positive])}",
        source_type: "direct_upload",
        access_mode: "specific_tiers",
        owner_email: "owner@example.com",
        tier_plan_ids: [world.plan.id]
      })

    Map.put(world, :show, show)
  end

  then_ "a subscriber on that plan can access the show", fn world ->
    viewer = insert(:subscribed_viewer, organization: world.org)

    insert(:viewer_subscription,
      organization: world.org,
      viewer: viewer,
      plan: world.plan,
      status: "active"
    )

    assert Podcasts.can_access?(world.show, viewer)
    world
  end

  then_ "a subscriber on a different plan cannot access the show", fn world ->
    other_plan = insert(:plan, organization: world.org)
    viewer = insert(:subscribed_viewer, organization: world.org)

    insert(:viewer_subscription,
      organization: world.org,
      viewer: viewer,
      plan: other_plan,
      status: "active"
    )

    refute Podcasts.can_access?(world.show, viewer)
    world
  end

  # ---- Feed delivery ------------------------------------------------------

  given_ "a published podcast show exists with a ready episode", fn world ->
    org = Map.get(world, :org) || insert(:organization)

    show =
      insert(:podcast_show,
        organization: org,
        access_mode: "any_active",
        published: true
      )

    episode =
      insert(:podcast_episode,
        organization: org,
        show: show,
        status: "published",
        mux_playback_id: "pb_acceptance_#{System.unique_integer([:positive])}"
      )

    Map.merge(world, %{org: org, show: show, episode: episode})
  end

  given_ "a subscriber has an active feed token for the show", fn world ->
    viewer = insert(:subscribed_viewer, organization: world.org, subscription_status: "active")
    {:ok, token} = Podcasts.issue_feed_token(world.show, viewer)
    Map.merge(world, %{viewer: viewer, feed_token: token})
  end

  when_ "the subscriber's app fetches the feed URL", fn world ->
    {:ok, token} = Podcasts.get_usable_feed_token(world.feed_token.token)

    audio_url_fun = fn %Episode{id: id} -> "https://test.example/audio/#{id}.mp3" end

    xml =
      Bobine.Podcasts.FeedXml.render(
        world.show,
        token,
        Podcasts.list_published_episodes(world.show),
        audio_url_fun,
        feed_url: "https://test.example/feed.xml"
      )

    Map.put(world, :feed_xml, xml)
  end

  then_ "the feed responds with iTunes-namespaced RSS XML", fn world ->
    assert world.feed_xml =~ "xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\""
    assert world.feed_xml =~ "<rss"
    world
  end

  then_ "the response includes the episode's enclosure URL", fn world ->
    assert world.feed_xml =~ "https://test.example/audio/#{world.episode.id}.mp3"
    world
  end

  # ---- Revocation ---------------------------------------------------------

  when_ "the operator revokes the token", fn world ->
    {:ok, _} = Podcasts.revoke_feed_token(world.feed_token, "operator-revoked")
    world
  end

  then_ "the feed URL no longer serves audio for that subscriber", fn world ->
    assert {:error, :revoked} = Podcasts.get_usable_feed_token(world.feed_token.token)
    world
  end

  # ---- Regeneration -------------------------------------------------------

  when_ "the subscriber regenerates their feed URL", fn world ->
    {:ok, fresh} = Podcasts.regenerate_feed_token(world.show, world.viewer)
    Map.put(world, :fresh_token, fresh)
  end

  then_ "a fresh token is issued", fn world ->
    refute world.fresh_token.token == world.feed_token.token
    assert world.fresh_token.status == "active"
    world
  end

  then_ "the previous URL is revoked", fn world ->
    assert %FeedToken{status: "revoked"} = Repo.get!(FeedToken, world.feed_token.id)
    world
  end

  # ---- Multi-tenant isolation --------------------------------------------

  given_ "two organizations each own a podcast show", fn world ->
    org_a = insert(:organization)
    org_b = insert(:organization)
    show_a = insert(:podcast_show, organization: org_a, published: true)
    show_b = insert(:podcast_show, organization: org_b, published: true)
    Map.merge(world, %{org_a: org_a, org_b: org_b, show_a: show_a, show_b: show_b})
  end

  then_ "operator A only sees their own show in the podcasts list", fn world ->
    %{results: shows} = Podcasts.list_shows(world.org_a, per_page: 100)
    ids = Enum.map(shows, & &1.id)
    assert world.show_a.id in ids
    refute world.show_b.id in ids
    world
  end

  then_ "operator B only sees their own show in the podcasts list", fn world ->
    %{results: shows} = Podcasts.list_shows(world.org_b, per_page: 100)
    ids = Enum.map(shows, & &1.id)
    assert world.show_b.id in ids
    refute world.show_a.id in ids
    world
  end

  # ---- Mux webhook --------------------------------------------------------

  given_ "a draft episode exists waiting on Mux processing", fn world ->
    org = Map.get(world, :org) || insert(:organization)
    show = insert(:podcast_show, organization: org)

    episode =
      insert(:podcast_episode,
        organization: org,
        show: show,
        mux_asset_id: "asset_acceptance_#{System.unique_integer([:positive])}",
        mux_playback_id: nil,
        mux_status: "preparing",
        status: "processing"
      )

    Map.merge(world, %{org: org, show: show, episode: episode})
  end

  when_ "Mux signals that the audio asset is ready", fn world ->
    {:ok, updated} =
      Podcasts.mark_episode_ready(world.episode.mux_asset_id, %{
        playback_id: "pb_ready_#{System.unique_integer([:positive])}",
        duration: 600.0,
        mp3_byte_size: 1_000_000
      })

    Map.put(world, :episode, updated)
  end

  then_ "the episode status becomes published", fn world ->
    assert world.episode.status == "published"
    world
  end

  then_ "its mux_playback_id is set", fn world ->
    assert is_binary(world.episode.mux_playback_id)
    world
  end

  # ---- Operator scope helpers --------------------------------------------

  # Provided so `Given I am logged in as an operator …` works without
  # requiring a Wallaby session for the no-server cucumber suite.
  given_ "I am an operator without a session", fn world ->
    seed_operator_scope(world, :owner)
  end

  defp seed_operator_scope(world, role) do
    if Map.has_key?(world, :scope) and Map.has_key?(world, :org) do
      world
    else
      org = insert(:organization)
      user = insert(:user, confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
      membership = insert(:membership, user: user, organization: org, role: role)
      scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
      Map.merge(world, %{org: org, operator: user, membership: membership, scope: scope})
    end
  end
end
