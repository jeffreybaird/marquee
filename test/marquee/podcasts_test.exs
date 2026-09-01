defmodule Marquee.PodcastsTest do
  use Marquee.DataCase

  import Mox

  alias Marquee.Accounts.Scope
  alias Marquee.Content.MockMuxClient
  alias Marquee.Podcasts
  alias Marquee.Podcasts.{AudioRequest, Episode, FeedToken, Show, ShowTier}

  setup :verify_on_exit!

  setup do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :editor)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)
    %{org: org, user: user, scope: scope}
  end

  describe "shows" do
    test "list_shows/2 returns paginated, non-deleted shows", %{org: org} do
      _kept = insert(:podcast_show, organization: org, title: "B")
      _other = insert(:podcast_show, organization: org, title: "A")

      _deleted =
        insert(:podcast_show,
          organization: org,
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert %{results: results, total: 2} = Podcasts.list_shows(org)
      assert Enum.map(results, & &1.title) == ["A", "B"]
    end

    test "get_show/2 scopes by org", %{org: org} do
      show = insert(:podcast_show, organization: org)
      other_org = insert(:organization)
      assert {:ok, found} = Podcasts.get_show(org, show.id)
      assert found.id == show.id
      assert {:error, :not_found} = Podcasts.get_show(other_org, show.id)
    end

    test "create_show/2 inserts show + tier rows when access_mode is specific_tiers",
         %{scope: scope, org: org} do
      plan_a = insert(:plan, organization: org)
      plan_b = insert(:plan, organization: org)

      attrs = %{
        title: "Premium Talk",
        slug: "premium-talk",
        source_type: "direct_upload",
        access_mode: "specific_tiers",
        owner_email: "owner@example.com",
        tier_plan_ids: [plan_a.id, plan_b.id]
      }

      assert {:ok, %Show{} = show} = Podcasts.create_show(scope, attrs)
      assert show.organization_id == org.id
      assert length(show.show_tiers) == 2

      assert Enum.sort(Enum.map(show.access_plans, & &1.id)) ==
               Enum.sort([plan_a.id, plan_b.id])
    end

    test "create_show/2 returns validation error for bad slug", %{scope: scope} do
      attrs = %{
        title: "Bad",
        slug: "Bad Slug!",
        source_type: "direct_upload",
        access_mode: "any_active"
      }

      assert {:error, :validation, %Ecto.Changeset{}} = Podcasts.create_show(scope, attrs)
    end

    test "update_show/3 replaces tier list when given", %{scope: scope, org: org} do
      show = insert(:podcast_show, organization: org, access_mode: "specific_tiers")
      old_plan = insert(:plan, organization: org)
      insert(:podcast_show_tier, organization: org, show: show, plan: old_plan)
      new_plan = insert(:plan, organization: org)

      assert {:ok, updated} = Podcasts.update_show(scope, show, %{tier_plan_ids: [new_plan.id]})

      tiers = Repo.all(from t in ShowTier, where: t.show_id == ^updated.id)
      assert Enum.map(tiers, & &1.plan_id) == [new_plan.id]
    end

    test "soft_delete_show/2 marks deleted_at and revokes active tokens",
         %{scope: scope, org: org} do
      show = insert(:podcast_show, organization: org)
      viewer = insert(:subscribed_viewer, organization: org)
      token = insert(:podcast_feed_token, organization: org, show: show, viewer: viewer)

      assert {:ok, %Show{deleted_at: %DateTime{}}} = Podcasts.soft_delete_show(scope, show)

      assert %FeedToken{status: "revoked", revoked_reason: "show_deleted"} =
               Repo.get!(FeedToken, token.id)

      assert {:error, :not_found} = Podcasts.get_show(show.organization, show.id)
    end
  end

  describe "audio uploads" do
    test "create_audio_upload_url/3 returns episode + URL for direct_upload show",
         %{scope: scope, org: org} do
      show = insert(:podcast_show, organization: org, source_type: "direct_upload")

      expect(MockMuxClient, :create_audio_direct_upload, fn params ->
        assert params.new_asset_settings.mp3_support == "audio-only"
        {:ok, %{"id" => "upload_audio_1", "url" => "https://mux.test/upload_audio_1"}}
      end)

      assert {:ok, %{episode: ep, upload_url: url}} =
               Podcasts.create_audio_upload_url(scope, show, %{title: "Pilot"})

      assert ep.show_id == show.id
      assert ep.organization_id == org.id
      assert ep.mux_upload_id == "upload_audio_1"
      assert ep.mux_status == "waiting"
      assert url == "https://mux.test/upload_audio_1"
    end

    test "create_audio_upload_url/3 refuses feed_import shows",
         %{scope: scope, org: org} do
      show = insert(:feed_import_show, organization: org)

      assert {:error, :unsupported_source, "feed_import"} =
               Podcasts.create_audio_upload_url(scope, show, %{title: "x"})
    end
  end

  describe "Mux webhook hooks" do
    test "link_audio_upload_to_asset/2 attaches asset id and flips status to preparing",
         %{org: org} do
      show = insert(:podcast_show, organization: org)

      ep =
        insert(:podcast_episode,
          organization: org,
          show: show,
          mux_upload_id: "u1",
          mux_asset_id: nil,
          mux_status: "waiting"
        )

      assert {:ok, updated} = Podcasts.link_audio_upload_to_asset("u1", "asset_1")
      assert updated.id == ep.id
      assert updated.mux_asset_id == "asset_1"
      assert updated.mux_status == "preparing"
    end

    test "link_audio_upload_to_asset/2 returns :not_found when no episode owns the upload" do
      assert {:error, :not_found} = Podcasts.link_audio_upload_to_asset("missing", "asset")
    end

    test "mark_episode_ready/2 publishes episode and stores playback id",
         %{org: org} do
      show = insert(:podcast_show, organization: org)

      ep =
        insert(:podcast_episode,
          organization: org,
          show: show,
          mux_asset_id: "asset_ready",
          mux_status: "preparing",
          status: "processing"
        )

      assert {:ok, updated} =
               Podcasts.mark_episode_ready("asset_ready", %{
                 playback_id: "pb_1",
                 duration: 120.4,
                 mp3_byte_size: 9_000_000
               })

      assert updated.id == ep.id
      assert updated.mux_status == "ready"
      assert updated.status == "published"
      assert updated.mux_playback_id == "pb_1"
      assert updated.duration_seconds == 120
      assert updated.mp3_byte_size == 9_000_000
    end

    test "mark_episode_ready/2 returns :not_found for unknown asset" do
      assert {:error, :not_found} = Podcasts.mark_episode_ready("nope", %{})
    end

    test "mark_episode_errored/2 records the error message", %{org: org} do
      show = insert(:podcast_show, organization: org)

      insert(:podcast_episode,
        organization: org,
        show: show,
        mux_asset_id: "asset_err",
        mux_status: "preparing",
        status: "processing"
      )

      assert {:ok, updated} =
               Podcasts.mark_episode_errored("asset_err", %{message: ["bad audio"]})

      assert updated.mux_status == "errored"
      assert updated.status == "errored"
      assert updated.error_message == "bad audio"
    end
  end

  describe "feed import" do
    test "upsert_episode_from_feed/2 inserts a new episode", %{org: org} do
      show = insert(:feed_import_show, organization: org)

      assert {:ok, %Episode{} = ep} =
               Podcasts.upsert_episode_from_feed(show, %{
                 guid: "rss-1",
                 title: "Pilot",
                 description: "first",
                 episode_number: 1,
                 episode_type: "full",
                 publish_date: DateTime.utc_now() |> DateTime.truncate(:second),
                 duration_seconds: 600,
                 remote_audio_url: "https://feed.example/ep1.mp3"
               })

      assert ep.guid == "rss-1"
      assert ep.show_id == show.id
      assert ep.remote_audio_url == "https://feed.example/ep1.mp3"
    end

    test "upsert_episode_from_feed/2 updates existing but preserves locked fields",
         %{org: org} do
      show = insert(:feed_import_show, organization: org)

      existing =
        insert(:podcast_episode,
          organization: org,
          show: show,
          guid: "rss-2",
          title: "Operator-edited title",
          locked_fields: ["title"]
        )

      assert {:ok, updated} =
               Podcasts.upsert_episode_from_feed(show, %{
                 guid: "rss-2",
                 title: "Feed wants this title",
                 description: "feed body"
               })

      assert updated.id == existing.id
      assert updated.title == "Operator-edited title"
      assert updated.description == "feed body"
    end

    test "upsert_episode_from_feed/2 errors without a guid", %{org: org} do
      show = insert(:feed_import_show, organization: org)
      assert {:error, :missing_guid} = Podcasts.upsert_episode_from_feed(show, %{title: "x"})
    end
  end

  describe "feed tokens" do
    test "issue_feed_token/2 mints one and reuses on second call", %{org: org} do
      show = insert(:podcast_show, organization: org)
      viewer = insert(:subscribed_viewer, organization: org)

      assert {:ok, t1} = Podcasts.issue_feed_token(show, viewer)
      assert t1.status == "active"

      assert {:ok, t2} = Podcasts.issue_feed_token(show, viewer)
      assert t2.id == t1.id
    end

    test "revoke_feed_token/2 marks revoked and is idempotent", %{org: org} do
      show = insert(:podcast_show, organization: org)
      viewer = insert(:subscribed_viewer, organization: org)
      {:ok, token} = Podcasts.issue_feed_token(show, viewer)

      assert {:ok, %FeedToken{status: "revoked"} = revoked} =
               Podcasts.revoke_feed_token(token, "test")

      assert {:ok, ^revoked} = Podcasts.revoke_feed_token(revoked, "test")
    end

    test "regenerate_feed_token/2 revokes old + mints new", %{org: org} do
      show = insert(:podcast_show, organization: org)
      viewer = insert(:subscribed_viewer, organization: org)
      {:ok, old} = Podcasts.issue_feed_token(show, viewer)

      assert {:ok, fresh} = Podcasts.regenerate_feed_token(show, viewer)
      assert fresh.id != old.id
      assert Repo.get!(FeedToken, old.id).status == "revoked"
    end

    test "get_usable_feed_token/1 only returns active, unexpired tokens", %{org: org} do
      show = insert(:podcast_show, organization: org)
      v1 = insert(:subscribed_viewer, organization: org)
      v2 = insert(:subscribed_viewer, organization: org)
      active = insert(:podcast_feed_token, organization: org, show: show, viewer: v1)

      revoked =
        insert(:podcast_feed_token, organization: org, show: show, viewer: v2, status: "revoked")

      assert {:ok, t} = Podcasts.get_usable_feed_token(active.token)
      assert t.id == active.id
      assert {:error, :revoked} = Podcasts.get_usable_feed_token(revoked.token)
      assert {:error, :not_found} = Podcasts.get_usable_feed_token("does-not-exist")
    end
  end

  describe "audio request log" do
    test "log_audio_request/1 inserts a row with default occurred_at", %{org: org} do
      show = insert(:podcast_show, organization: org)
      ep = insert(:podcast_episode, organization: org, show: show)

      assert {:ok, %AudioRequest{} = record} =
               Podcasts.log_audio_request(%{
                 organization_id: org.id,
                 show_id: show.id,
                 episode_id: ep.id,
                 request_type: "audio_redirect"
               })

      assert record.occurred_at != nil
    end

    test "request_counts_for_show/2 groups by request_type", %{org: org} do
      show = insert(:podcast_show, organization: org)
      ep = insert(:podcast_episode, organization: org, show: show)

      for type <- ["feed", "feed", "audio_redirect"] do
        Podcasts.log_audio_request(%{
          organization_id: org.id,
          show_id: show.id,
          episode_id: ep.id,
          request_type: type
        })
      end

      since = DateTime.utc_now() |> DateTime.add(-3600, :second)
      assert %{"feed" => 2, "audio_redirect" => 1} = Podcasts.request_counts_for_show(show, since)
    end
  end

  describe "access" do
    test "can_access?/2 grants when viewer has any active subscription on any_active show",
         %{org: org} do
      show = insert(:podcast_show, organization: org, access_mode: "any_active")
      viewer = insert(:subscribed_viewer, organization: org, subscription_status: "active")
      assert Podcasts.can_access?(show, viewer)
    end

    test "can_access?/2 denies on specific_tiers when viewer's plan is not listed",
         %{org: org} do
      plan_allowed = insert(:plan, organization: org)
      plan_other = insert(:plan, organization: org)
      show = insert(:podcast_show, organization: org, access_mode: "specific_tiers")
      insert(:podcast_show_tier, organization: org, show: show, plan: plan_allowed)

      viewer = insert(:subscribed_viewer, organization: org)

      insert(:viewer_subscription,
        organization: org,
        viewer: viewer,
        plan: plan_other,
        status: "active"
      )

      refute Podcasts.can_access?(show, viewer)
    end
  end
end
