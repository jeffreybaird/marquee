defmodule Bobine.Podcasts.AudioProxyTest do
  use Bobine.DataCase, async: false

  import Mox

  alias Bobine.Podcasts.{AudioProxy, Episode}
  alias Bobine.Storage.MockSpacesClient

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    on_exit(fn -> Application.delete_env(:bobine, :podcast_upstream_fetcher) end)
    :ok
  end

  doctest AudioProxy, import: true

  setup do
    org = insert(:organization)
    show = insert(:feed_import_show, organization: org)

    episode =
      insert(:podcast_episode,
        organization: org,
        show: show,
        remote_audio_url: "https://upstream.test/episode.mp3",
        remote_audio_content_type: "audio/mpeg",
        mux_playback_id: nil,
        mux_asset_id: nil
      )

    %{episode: episode}
  end

  describe "fetch_audio/1" do
    test "returns the cached body on a hit", %{episode: episode} do
      expect(MockSpacesClient, :head_object, fn _key ->
        {:ok, %{content_type: "audio/mpeg", size: 7}}
      end)

      expect(MockSpacesClient, :download_object, fn _key ->
        {:ok, %{body: "cached!", content_type: "audio/mpeg"}}
      end)

      assert {:ok, %{body: "cached!", content_type: "audio/mpeg"}} =
               AudioProxy.fetch_audio(episode)
    end

    test "fetches upstream + writes to storage on a miss", %{episode: episode} do
      Application.put_env(:bobine, :podcast_upstream_fetcher, fn url ->
        assert url == episode.remote_audio_url
        {:ok, "episode-bytes", "audio/mpeg"}
      end)

      expect(MockSpacesClient, :head_object, fn _key -> {:error, :not_found} end)

      expect(MockSpacesClient, :put_object, fn key, body, content_type ->
        assert key =~ "podcast/"
        assert body == "episode-bytes"
        assert content_type == "audio/mpeg"
        :ok
      end)

      assert {:ok, %{body: "episode-bytes", content_type: "audio/mpeg"}} =
               AudioProxy.fetch_audio(episode)
    end

    test "still serves bytes when storage put fails", %{episode: episode} do
      Application.put_env(:bobine, :podcast_upstream_fetcher, fn _url ->
        {:ok, "fallback-bytes", "audio/mpeg"}
      end)

      expect(MockSpacesClient, :head_object, fn _key -> {:error, :not_found} end)
      expect(MockSpacesClient, :put_object, fn _, _, _ -> {:error, :unavailable} end)

      assert {:ok, %{body: "fallback-bytes"}} = AudioProxy.fetch_audio(episode)
    end

    test "returns upstream_failed on a non-200", %{episode: episode} do
      Application.put_env(:bobine, :podcast_upstream_fetcher, fn _url ->
        {:error, "upstream returned HTTP 503"}
      end)

      expect(MockSpacesClient, :head_object, fn _key -> {:error, :not_found} end)

      assert {:error, :upstream_failed, _} = AudioProxy.fetch_audio(episode)
    end

    test "returns :no_remote_audio when the episode has no upstream URL",
         %{episode: episode} do
      assert {:error, :no_remote_audio} =
               AudioProxy.fetch_audio(%{episode | remote_audio_url: nil})
    end
  end
end
