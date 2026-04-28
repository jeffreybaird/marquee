defmodule BobineWeb.PodcastFeedController do
  @moduledoc """
  Public, token-gated endpoints that serve a subscriber's podcast feed
  and audio.

  Two routes:

    * `GET /podcasts/:token/feed.xml` — RSS XML for the show paired
      with the token. Token must be active + unexpired and the viewer
      must still pass the show's access check.
    * `GET /podcasts/:token/episodes/:episode_id.mp3` — for direct-
      upload shows, redirects to the Mux MP3 URL; for feed-import shows,
      proxies the upstream audio (no caching of the bytes themselves —
      we redirect or stream).

  Every served request is logged to `podcast_audio_requests` so the
  operator analytics view has data.
  """

  use BobineWeb, :controller

  alias Bobine.Cache
  alias Bobine.Podcasts
  alias Bobine.Podcasts.{Episode, FeedToken, FeedXml, Show}
  alias Bobine.Repo

  @feed_cache_ttl_ms 60_000

  def feed(conn, %{"token" => token_value}) do
    with {:ok, %FeedToken{} = token} <- Podcasts.get_usable_feed_token(token_value),
         {:ok, show, viewer} <- load_show_and_viewer(token),
         true <- Podcasts.can_access?(show, viewer) || :forbidden do
      Podcasts.touch_feed_token(token)

      Podcasts.log_audio_request(%{
        organization_id: show.organization_id,
        show_id: show.id,
        episode_id: nil,
        viewer_id: viewer.id,
        feed_token_id: token.id,
        request_type: "feed",
        user_agent: get_req_header(conn, "user-agent") |> List.first()
      })

      xml = render_feed_cached(conn, show, token)

      conn
      |> put_resp_content_type("application/rss+xml")
      |> put_resp_header("cache-control", "private, max-age=60")
      |> send_resp(200, xml)
    else
      :forbidden -> send_resp(conn, 403, "")
      _ -> send_resp(conn, 404, "")
    end
  end

  def episode_audio(conn, %{"token" => token_value, "episode_id" => episode_id}) do
    with {:ok, %FeedToken{} = token} <- Podcasts.get_usable_feed_token(token_value),
         {:ok, show, viewer} <- load_show_and_viewer(token),
         true <- Podcasts.can_access?(show, viewer) || :forbidden,
         {:ok, %Episode{} = episode} <- load_owned_episode(show, episode_id) do
      Podcasts.touch_feed_token(token)

      request_type = if episode.mux_playback_id, do: "audio_redirect", else: "audio_proxy"

      Podcasts.log_audio_request(%{
        organization_id: show.organization_id,
        show_id: show.id,
        episode_id: episode.id,
        viewer_id: viewer.id,
        feed_token_id: token.id,
        request_type: request_type,
        user_agent: get_req_header(conn, "user-agent") |> List.first()
      })

      serve_audio(conn, show, episode)
    else
      :forbidden -> send_resp(conn, 403, "")
      _ -> send_resp(conn, 404, "")
    end
  end

  defp load_show_and_viewer(%FeedToken{show_id: show_id, viewer_id: viewer_id}) do
    with %Show{deleted_at: nil} = show <- Repo.get(Show, show_id) |> Podcasts.with_access_plans(),
         %_{} = viewer <- Repo.get(Bobine.Viewers.Viewer, viewer_id) do
      {:ok, show, viewer}
    else
      _ -> {:error, :not_found}
    end
  end

  defp load_owned_episode(%Show{id: show_id}, episode_id) do
    case Repo.get(Episode, episode_id) do
      %Episode{show_id: ^show_id, deleted_at: nil, status: "published"} = ep -> {:ok, ep}
      _ -> {:error, :not_found}
    end
  end

  defp serve_audio(conn, _show, %Episode{mux_playback_id: playback_id})
       when is_binary(playback_id) do
    redirect(conn, external: "https://stream.mux.com/#{playback_id}/audio.mp3")
  end

  defp serve_audio(conn, _show, %Episode{remote_audio_url: url}) when is_binary(url) do
    redirect(conn, external: url)
  end

  defp serve_audio(conn, _show, _episode), do: send_resp(conn, 404, "")

  defp render_feed_cached(_conn, %Show{} = show, %FeedToken{} = token) do
    key = {:podcast_feed_xml, token.id}

    Cache.fetch(key, [ttl: @feed_cache_ttl_ms], fn ->
      episodes = Podcasts.list_published_episodes(show)
      feed_url = BobineWeb.Endpoint.url() <> "/podcasts/#{token.token}/feed.xml"

      audio_url_fun = fn %Episode{id: ep_id} ->
        BobineWeb.Endpoint.url() <>
          "/podcasts/#{token.token}/episodes/#{ep_id}/audio.mp3"
      end

      FeedXml.render(show, token, episodes, audio_url_fun, feed_url: feed_url)
    end)
  end
end
