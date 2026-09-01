defmodule Marquee.Podcasts.RemoteFeedClient do
  @moduledoc """
  HTTP fetcher for remote podcast RSS feeds. Wraps `Req` so tests can swap
  the implementation via Application config.
  """

  @callback fetch(url :: String.t()) ::
              {:ok, %{status: integer(), body: binary(), headers: list()}}
              | {:error, term()}

  @doc "Fetches a remote feed via Req with reasonable timeouts."
  def fetch(url) do
    impl().fetch(url)
  end

  defp impl do
    Application.get_env(:marquee, :remote_feed_client, __MODULE__.Default)
  end

  defmodule Default do
    @moduledoc false
    @behaviour Marquee.Podcasts.RemoteFeedClient

    @impl true
    def fetch(url) do
      case Req.get(url, receive_timeout: 30_000, retry: false) do
        {:ok, %Req.Response{status: status, body: body, headers: headers}} ->
          {:ok, %{status: status, body: to_string(body), headers: headers}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
