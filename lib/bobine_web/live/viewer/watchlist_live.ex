defmodule BobineWeb.Viewer.WatchlistLive do
  use BobineWeb, :live_view

  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Watchlist")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/watchlist"
      flash={@flash}
    >
      <div class="max-w-2xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
        <.header>Watchlist</.header>
        <p class="mt-4 text-base-content/70">Your watchlist coming soon.</p>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
