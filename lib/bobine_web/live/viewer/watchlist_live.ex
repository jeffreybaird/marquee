defmodule BobineWeb.Viewer.WatchlistLive do
  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Watchlist")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_viewer={@current_viewer}
      organization={@organization}
    >
      <.header>Watchlist</.header>
      <p class="mt-4 text-base-content/70">Your watchlist coming soon.</p>
    </Layouts.app>
    """
  end
end
