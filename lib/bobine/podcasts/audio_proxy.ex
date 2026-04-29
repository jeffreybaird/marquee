defmodule Bobine.Podcasts.AudioProxy do
  @moduledoc """
  Caches feed-import episode audio in `Bobine.Storage` so the upstream
  publisher's URL is never handed to the subscriber's app.

  Direct-upload episodes ride Mux's per-asset playback IDs, which are
  themselves capability tokens — those still 302 to Mux from the
  controller. Feed-import episodes were leaking the publisher's raw
  upstream URL on every redirect, breaking the access gate. This module
  pulls the bytes once, stores them under an org-namespaced key, and on
  every subsequent request streams them from cache.

  In dev the storage backend is `Bobine.Storage.LocalClient` (files on
  disk under priv/static/uploads). In staging / prod it's the real
  DigitalOcean Spaces client. The proxy is agnostic to which one is
  active — it asks `Bobine.Storage` to head, put, or download.
  """

  require Logger

  alias Bobine.Podcasts.Episode
  alias Bobine.Storage

  @doc """
  Returns the storage key for an episode's cached audio. Public so the
  Mux webhook + token reconciler can purge a cached entry when the
  episode is withdrawn (future work).

      iex> alias Bobine.Podcasts.{AudioProxy, Episode}
      iex> AudioProxy.cache_key(%Episode{
      ...>   id: "ep-1",
      ...>   organization_id: "org-1",
      ...>   show_id: "show-1"
      ...> })
      "org/org-1/podcast/show-1/ep-1.mp3"
  """
  def cache_key(%Episode{id: id, organization_id: org_id, show_id: show_id}) do
    "org/#{org_id}/podcast/#{show_id}/#{id}.mp3"
  end

  @doc """
  Returns the bytes + content type for an episode, fetching upstream
  and writing them to storage on a cache miss. Caller is responsible
  for sending the response.

  Returns:

    * `{:ok, %{body: binary, content_type: String.t}}` on success
    * `{:error, :no_remote_audio}` when the episode has no upstream URL
    * `{:error, :upstream_failed, reason}` when the fetch fails
    * `{:error, :storage_failed, reason}` when storage put/get fails

  Exempt from doctest — calls storage + remote fetch.
  """
  def fetch_audio(%Episode{remote_audio_url: nil}), do: {:error, :no_remote_audio}

  def fetch_audio(%Episode{remote_audio_url: url} = episode) when is_binary(url) do
    key = cache_key(episode)

    case Storage.head_object(key) do
      {:ok, _meta} -> read_cached(episode, key)
      {:error, :not_found} -> populate_cache(episode, key, url)
      {:error, reason} -> {:error, :storage_failed, reason}
    end
  end

  defp read_cached(episode, key) do
    case Storage.download_object(key) do
      {:ok, %{body: body, content_type: ct}} ->
        {:ok, %{body: body, content_type: ct || episode_content_type(episode)}}

      {:error, :not_found} ->
        # Race: head said yes, get said no. Fall through and re-populate.
        populate_cache(episode, key, episode.remote_audio_url)

      {:error, reason} ->
        {:error, :storage_failed, reason}
    end
  end

  defp populate_cache(episode, key, url) do
    case fetch_upstream(url) do
      {:ok, body, content_type} ->
        ct = content_type || episode_content_type(episode)

        case Storage.put_object(key, body, ct) do
          :ok ->
            {:ok, %{body: body, content_type: ct}}

          {:error, reason} ->
            Logger.warning("Failed to cache podcast audio",
              org_id: episode.organization_id,
              podcast_show_id: episode.show_id,
              key: key,
              reason: inspect(reason)
            )

            # Even if caching failed, we still have the bytes — serve them
            # rather than returning an error to the subscriber.
            {:ok, %{body: body, content_type: ct}}
        end

      {:error, reason} ->
        {:error, :upstream_failed, reason}
    end
  end

  @doc false
  def fetch_upstream(url) do
    fetcher = Application.get_env(:bobine, :podcast_upstream_fetcher, &default_fetch/1)
    fetcher.(url)
  end

  defp default_fetch(url) do
    case Req.get(url, receive_timeout: 60_000, retry: false, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        ct = headers |> List.wrap() |> header_value("content-type")
        {:ok, body, ct}

      {:ok, %Req.Response{status: status}} ->
        {:error, "upstream returned HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp header_value(headers, name) do
    target = String.downcase(name)

    Enum.find_value(headers, fn
      {k, v} when is_binary(k) and is_binary(v) ->
        if String.downcase(k) == target, do: v

      {k, [v | _]} when is_binary(k) and is_binary(v) ->
        if String.downcase(k) == target, do: v

      _ ->
        nil
    end)
  end

  defp episode_content_type(%Episode{remote_audio_content_type: ct}) when is_binary(ct), do: ct
  defp episode_content_type(_), do: "audio/mpeg"
end
