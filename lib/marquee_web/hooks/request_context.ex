defmodule MarqueeWeb.Hooks.RequestContext do
  @moduledoc """
  LiveView `on_mount` hook that records request context (client IP and user
  agent) for the LiveView process, so audit entries written from LiveView
  event handlers carry the same `ip` / `user_agent` metadata as entries
  written during a plain HTTP request.

  `MarqueeWeb.Plugs.SetRequestContext` covers the HTTP request process. A
  connected LiveView runs in its own process, so this hook rebuilds the
  context from the socket's connect info (`:peer_data`, `:user_agent`,
  configured on the `/live` socket in `MarqueeWeb.Endpoint`). A context
  already present in the process (the disconnected render, which runs inside
  the HTTP request) is left untouched.

  Attached to every LiveView through `MarqueeWeb.live_view/0`.
  """

  import Phoenix.LiveView, only: [get_connect_info: 2]

  alias Marquee.RequestContext

  def on_mount(:default, _params, _session, socket) do
    if is_nil(RequestContext.current()) do
      socket
      |> build_socket_request_context()
      |> RequestContext.put()
    end

    {:cont, socket}
  end

  defp build_socket_request_context(socket) do
    %{
      request_id: nil,
      ip: socket |> safe_connect_info(:peer_data) |> format_peer_ip(),
      user_agent: safe_connect_info(socket, :user_agent),
      scope: socket.assigns[:current_scope]
    }
  end

  # get_connect_info/2 raises outside mount and returns nil when the key was
  # not configured on the socket; treat both as "unknown".
  defp safe_connect_info(socket, key) do
    get_connect_info(socket, key)
  rescue
    RuntimeError -> nil
  end

  @doc """
  Formats the `:peer_data` connect info as an IP string, or `nil` when the
  peer address is unavailable.

      iex> MarqueeWeb.Hooks.RequestContext.format_peer_ip(%{address: {127, 0, 0, 1}, port: 4000})
      "127.0.0.1"

      iex> MarqueeWeb.Hooks.RequestContext.format_peer_ip(%{address: {0, 0, 0, 0, 0, 0, 0, 1}})
      "::1"

      iex> MarqueeWeb.Hooks.RequestContext.format_peer_ip(nil)
      nil
  """
  def format_peer_ip(%{address: address}) when is_tuple(address),
    do: address |> :inet.ntoa() |> to_string()

  def format_peer_ip(_), do: nil
end
