defmodule BobineWeb.PodcastFeedControllerTest do
  use BobineWeb.ConnCase, async: false

  import SweetXml

  alias Bobine.Cache
  alias Bobine.Podcasts
  alias Bobine.Repo

  setup do
    org = insert(:organization)
    plan = insert(:plan, organization: org)

    show = insert(:podcast_show, organization: org, access_mode: "any_active", published: true)

    viewer = insert(:subscribed_viewer, organization: org, subscription_status: "active")

    insert(:viewer_subscription,
      organization: org,
      viewer: viewer,
      plan: plan,
      status: "active"
    )

    {:ok, token} = Podcasts.issue_feed_token(show, viewer)

    ep =
      insert(:podcast_episode,
        organization: org,
        show: show,
        status: "published",
        mux_playback_id: "pb_abc"
      )

    on_exit(fn -> Cache.delete({:podcast_feed_xml, token.id}) end)

    %{org: org, show: show, viewer: viewer, token: token, episode: ep}
  end

  describe "GET /podcasts/:token/feed.xml" do
    test "renders RSS XML for an active token + accessible viewer", %{conn: conn, token: token} do
      conn = get(conn, ~p"/podcasts/#{token.token}/feed.xml")

      assert response_content_type(conn, :xml)
      body = response(conn, 200)
      assert body =~ "<rss"
      doc = SweetXml.parse(body)
      assert xpath(doc, ~x"//rss/channel/title/text()"s) != ""
    end

    test "404s on a nonexistent token", %{conn: conn} do
      conn = get(conn, ~p"/podcasts/does-not-exist/feed.xml")
      assert response(conn, 404)
    end

    test "404s on a revoked token", %{conn: conn, token: token} do
      Podcasts.revoke_feed_token(token, "test")
      conn = get(conn, ~p"/podcasts/#{token.token}/feed.xml")
      assert response(conn, 404)
    end

    test "403s when the viewer no longer has access", %{
      conn: conn,
      org: org,
      viewer: viewer,
      token: token
    } do
      # Cancel the only active subscription
      {:ok, sub} = Bobine.Billing.get_active_viewer_subscription(org, viewer)
      Repo.update!(Ecto.Changeset.change(sub, status: "canceled"))

      alias Bobine.Viewers.Viewer

      Repo.update!(Viewer.subscription_changeset(viewer, %{subscription_status: "canceled"}))

      Cache.delete({:podcast_feed_xml, token.id})

      conn = get(conn, ~p"/podcasts/#{token.token}/feed.xml")
      assert response(conn, 403)
    end

    test "logs a feed request and increments token usage", %{
      conn: conn,
      token: token,
      show: show
    } do
      get(conn, ~p"/podcasts/#{token.token}/feed.xml")

      reloaded = Repo.get!(Podcasts.FeedToken, token.id)
      assert reloaded.request_count >= 1

      since = DateTime.utc_now() |> DateTime.add(-60, :second)
      counts = Podcasts.request_counts_for_show(show, since)
      assert Map.get(counts, "feed", 0) >= 1
    end
  end

  describe "GET /podcasts/:token/episodes/:episode_id/audio.mp3" do
    test "redirects to the Mux MP3 URL for direct-upload episodes",
         %{conn: conn, token: token, episode: ep} do
      conn = get(conn, ~p"/podcasts/#{token.token}/episodes/#{ep.id}/audio.mp3")

      assert redirected_to(conn, 302) =~ "stream.mux.com"
      assert redirected_to(conn, 302) =~ ep.mux_playback_id
    end

    test "404s for an episode that does not belong to the token's show",
         %{conn: conn, token: token, org: org} do
      other_show = insert(:podcast_show, organization: org)

      other_ep =
        insert(:podcast_episode, organization: org, show: other_show, status: "published")

      conn = get(conn, ~p"/podcasts/#{token.token}/episodes/#{other_ep.id}/audio.mp3")
      assert response(conn, 404)
    end
  end
end
