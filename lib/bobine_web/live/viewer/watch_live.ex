defmodule BobineWeb.Viewer.WatchLive do
  use BobineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Watch")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Watch</.header>
      <p class="mt-4 text-base-content/70">Video player coming soon.</p>
    </Layouts.app>
    """
  end
end
