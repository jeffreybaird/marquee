defmodule Marquee.SubscriberDemoTest do
  use Marquee.DataCase, async: false
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.Buffers.ProgressBuffer
  alias Marquee.Engagement
  alias Marquee.SubscriberDemo
  alias Marquee.Viewers
  alias Marquee.Viewers.Viewer

  setup do
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})

    video =
      insert(:video, organization: org, published: true, mux_status: "ready", duration: 180.0)

    %{org: org, video: video}
  end

  test "only explicitly enabled organizations offer the demo regardless of slug", %{org: org} do
    assert SubscriberDemo.enabled?(org)
    refute SubscriberDemo.enabled?(%{org | features: %{}})
    other = insert(:organization, features: %{"subscriber_demo" => true})
    assert SubscriberDemo.enabled?(other)
    insert(:video, organization: other, published: true, mux_status: "ready", duration: 180.0)
    assert {:ok, %{viewer: viewer}} = SubscriberDemo.start_session(other)
    assert viewer.organization_id == other.id
    refute SubscriberDemo.enabled?(%{other | features: %{"subscriber_demo" => "true"}})
    refute SubscriberDemo.enabled?(%{other | features: %{"subscriber_demo" => false}})
    assert {:error, :forbidden} = SubscriberDemo.start_session(%{org | features: %{}})
  end

  test "visitors get distinct passwordless subscribed identities and populated activity", %{
    org: org
  } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %{viewer: first, token: token}} = SubscriberDemo.start_session(org)
      assert {:ok, %{viewer: second}} = SubscriberDemo.start_session(org)
      assert first.id != second.id
      assert first.organization_id == org.id
      assert first.confirmed_at
      assert is_nil(first.hashed_password)
      assert is_nil(first.stripe_customer_id)
      assert first.subscription_status == "active"
      refute first.__preview__
      assert SubscriberDemo.demo_viewer?(first)
      refute SubscriberDemo.expired?(first)
      assert Viewers.get_viewer_by_session_token(token).id == first.id

      assert_enqueued(
        worker: Marquee.Workers.SubscriberDemoCleanup,
        args: %{organization_id: org.id}
      )

      assert Engagement.list_continue_watching(org, first).results != []
      assert Engagement.list_watch_history(org, first).results != []
    end)
  end

  test "watchlist and progress belong to their visitor", %{org: org, video: video} do
    {:ok, %{viewer: first}} = SubscriberDemo.start_session(org)
    {:ok, %{viewer: second}} = SubscriberDemo.start_session(org)
    second_position = Engagement.get_progress(org, second, video)
    assert {:ok, _} = Engagement.add_to_watchlist(org, first, video)
    assert :ok = Engagement.update_progress(org, first, video.id, 75, 180)
    assert Engagement.in_watchlist?(org, first, video)
    refute Engagement.in_watchlist?(org, second, video)
    assert Engagement.get_progress(org, first, video).position == 75
    assert Engagement.get_progress(org, second, video) == second_position
  end

  test "marked demo viewers with malformed or missing expiry fail closed", %{org: org} do
    for expiry <- [nil, "not-a-timestamp"] do
      metadata = %{"subscriber_demo" => true, "subscriber_demo_expires_at" => expiry}
      viewer = insert(:subscribed_viewer, organization: org, metadata: metadata)
      token = Viewers.generate_viewer_session_token(viewer)
      assert SubscriberDemo.demo_viewer?(viewer)
      assert SubscriberDemo.expired?(viewer)
      assert is_nil(Viewers.get_viewer_by_session_token(token))
    end

    regular = insert(:subscribed_viewer, organization: org)
    refute SubscriberDemo.expired?(regular)

    assert Viewers.get_viewer_by_session_token(Viewers.generate_viewer_session_token(regular)).id ==
             regular.id
  end

  test "expiry revokes tokens and cleanup deletes only expired demo data", %{
    org: org,
    video: video
  } do
    {:ok, %{viewer: expired, token: token}} = SubscriberDemo.start_session(org)
    {:ok, %{viewer: active}} = SubscriberDemo.start_session(org)
    regular = insert(:subscribed_viewer, organization: org)
    {:ok, _} = Engagement.add_to_watchlist(org, expired, video)
    :ok = Engagement.update_progress(org, expired, video.id, 80, 180)
    past = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601()
    other_org = insert(:organization)

    other =
      insert(:subscribed_viewer,
        organization: other_org,
        metadata: %{"subscriber_demo" => true, "subscriber_demo_expires_at" => past}
      )

    expired =
      expired
      |> Ecto.Changeset.change(
        metadata: Map.put(expired.metadata, "subscriber_demo_expires_at", past)
      )
      |> Repo.update!()

    assert SubscriberDemo.expired?(expired)
    assert is_nil(Viewers.get_viewer_by_session_token(token))
    assert {:error, :demo_expired} = Engagement.add_to_watchlist(org, expired, video)
    assert {:error, :demo_expired} = Engagement.update_progress(org, expired, video.id, 90, 180)
    assert {:ok, 1} = SubscriberDemo.cleanup_expired(org, now: DateTime.utc_now())
    assert is_nil(Repo.get(Viewer, expired.id))
    assert Repo.get(Viewer, active.id)
    assert Repo.get(Viewer, regular.id)
    assert Repo.get(Viewer, other.id)
    assert ProgressBuffer.list_viewer_entries(org.id, expired.id) == []
    refute Repo.exists?(from t in Marquee.Viewers.ViewerToken, where: t.viewer_id == ^expired.id)
    refute Repo.exists?(from p in Marquee.Engagement.Progress, where: p.viewer_id == ^expired.id)

    refute Repo.exists?(
             from w in Marquee.Engagement.WatchlistItem, where: w.viewer_id == ^expired.id
           )

    refute Repo.exists?(
             from h in Marquee.Engagement.WatchHistory, where: h.viewer_id == ^expired.id
           )

    assert {:ok, 0} = SubscriberDemo.cleanup_expired(org, now: DateTime.utc_now())
  end

  test "catalog seeding is repeatable and supplies series episodes and small collections", %{
    org: org
  } do
    previous = Application.fetch_env(:marquee, :subscriber_demo_catalog)

    Application.put_env(
      :marquee,
      :subscriber_demo_catalog,
      Marquee.SubscriberDemoFixtures.catalog_manifest()
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:marquee, :subscriber_demo_catalog, value)
        :error -> Application.delete_env(:marquee, :subscriber_demo_catalog)
      end
    end)

    assert {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    assert length(catalog.videos) >= 3
    assert length(catalog.collections) in 2..3
    assert catalog.series.organization_id == org.id

    episodes =
      Repo.all(
        from e in Marquee.Content.Episode,
          join: s in Marquee.Content.Season,
          on: e.season_id == s.id,
          where: s.series_id == ^catalog.series.id,
          order_by: e.episode_number
      )

    assert Enum.map(episodes, & &1.video_id) == Enum.map(catalog.videos, & &1.id)
    assert Enum.map(episodes, & &1.episode_number) == Enum.to_list(1..length(catalog.videos))

    for video <- catalog.videos do
      assert video.organization_id == org.id
      assert video.published
      assert video.mux_status == "ready"
      assert video.mux_playback_id not in [nil, "", "pending"]
      assert video.description not in [nil, ""]
    end

    assert {:ok, again} = SubscriberDemo.seed_catalog(org)
    assert again.series.id == catalog.series.id
    assert Enum.map(again.videos, & &1.id) == Enum.map(catalog.videos, & &1.id)
    assert Enum.map(again.collections, & &1.id) == Enum.map(catalog.collections, & &1.id)
  end
end
