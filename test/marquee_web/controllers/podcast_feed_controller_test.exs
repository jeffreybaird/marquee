defmodule MarqueeWeb.PodcastFeedControllerTest do
  use MarqueeWeb.ConnCase, async: false

  import Mox
  import SweetXml

  alias Marquee.Cache
  alias Marquee.Podcasts
  alias Marquee.Repo
  alias Marquee.Storage.MockSpacesClient

  setup :set_mox_from_context
  setup :verify_on_exit!

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
      {:ok, sub} = Marquee.Billing.get_active_viewer_subscription(org, viewer)
      Repo.update!(Ecto.Changeset.change(sub, status: "canceled"))

      alias Marquee.Viewers.Viewer

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

    test "feed-import episode streams cached bytes through the proxy",
         %{conn: conn, org: org, viewer: viewer} do
      feed_show =
        insert(:feed_import_show, organization: org, access_mode: "any_active", published: true)

      feed_ep =
        insert(:podcast_episode,
          organization: org,
          show: feed_show,
          status: "published",
          mux_playback_id: nil,
          mux_asset_id: nil,
          remote_audio_url: "https://upstream.test/ep.mp3",
          remote_audio_content_type: "audio/mpeg"
        )

      {:ok, feed_token} = Podcasts.issue_feed_token(feed_show, viewer)

      Application.put_env(:marquee, :podcast_upstream_fetcher, fn _url ->
        {:ok, "PROXY-BYTES", "audio/mpeg"}
      end)

      on_exit(fn -> Application.delete_env(:marquee, :podcast_upstream_fetcher) end)

      expect(MockSpacesClient, :head_object, fn _key -> {:error, :not_found} end)
      expect(MockSpacesClient, :put_object, fn _, _, _ -> :ok end)

      conn = get(conn, ~p"/podcasts/#{feed_token.token}/episodes/#{feed_ep.id}/audio.mp3")

      assert response(conn, 200) == "PROXY-BYTES"
      assert get_resp_header(conn, "content-type") == ["audio/mpeg; charset=utf-8"]
    end
  end
end
