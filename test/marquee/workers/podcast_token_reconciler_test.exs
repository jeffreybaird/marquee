defmodule Marquee.Workers.PodcastTokenReconcilerTest do
  use Marquee.DataCase, async: true
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.Podcasts.FeedToken
  alias Marquee.Repo
  alias Marquee.Workers.PodcastTokenReconciler

  setup do
    org = insert(:organization)
    %{org: org}
  end

  describe "show sweep" do
    test "revokes tokens for viewers who lost access after a tier change",
         %{org: org} do
      kept_plan = insert(:plan, organization: org)
      removed_plan = insert(:plan, organization: org)

      show = insert(:podcast_show, organization: org, access_mode: "specific_tiers")
      insert(:podcast_show_tier, organization: org, show: show, plan: kept_plan)

      kept_viewer = insert(:subscribed_viewer, organization: org)

      insert(:viewer_subscription,
        organization: org,
        viewer: kept_viewer,
        plan: kept_plan,
        status: "active"
      )

      lost_viewer = insert(:subscribed_viewer, organization: org)

      insert(:viewer_subscription,
        organization: org,
        viewer: lost_viewer,
        plan: removed_plan,
        status: "active"
      )

      kept_token =
        insert(:podcast_feed_token, organization: org, show: show, viewer: kept_viewer)

      lost_token =
        insert(:podcast_feed_token, organization: org, show: show, viewer: lost_viewer)

      assert :ok = perform_job(PodcastTokenReconciler, %{"show_id" => show.id})

      assert %FeedToken{status: "active"} = Repo.get!(FeedToken, kept_token.id)

      assert %FeedToken{status: "revoked", revoked_reason: "show_access_changed"} =
               Repo.get!(FeedToken, lost_token.id)
    end
  end

  describe "viewer sweep" do
    test "revokes the viewer's tokens after they cancel", %{org: org} do
      show_a = insert(:podcast_show, organization: org, access_mode: "any_active")
      show_b = insert(:podcast_show, organization: org, access_mode: "any_active")

      viewer = insert(:viewer, organization: org, subscription_status: "canceled")

      token_a = insert(:podcast_feed_token, organization: org, show: show_a, viewer: viewer)
      token_b = insert(:podcast_feed_token, organization: org, show: show_b, viewer: viewer)

      assert :ok =
               perform_job(PodcastTokenReconciler, %{
                 "viewer_id" => viewer.id,
                 "reason" => "subscription_canceled"
               })

      assert %FeedToken{status: "revoked"} = Repo.get!(FeedToken, token_a.id)
      assert %FeedToken{status: "revoked"} = Repo.get!(FeedToken, token_b.id)
    end
  end

  describe "enqueue helpers" do
    test "enqueue_for_show/2 inserts a job", %{org: org} do
      show = insert(:podcast_show, organization: org)
      assert {:ok, %Oban.Job{}} = PodcastTokenReconciler.enqueue_for_show(show, "test")
    end

    test "enqueue_for_viewer/2 inserts a job", %{org: org} do
      viewer = insert(:viewer, organization: org)
      assert {:ok, %Oban.Job{}} = PodcastTokenReconciler.enqueue_for_viewer(viewer, "test")
    end
  end
end
