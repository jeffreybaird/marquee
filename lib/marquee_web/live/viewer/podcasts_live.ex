defmodule MarqueeWeb.Viewer.PodcastsLive do
  @moduledoc """
  Viewer-facing podcast directory. Lists all published shows for the org.

  Route: /podcasts (viewer_public session, optional auth)
  """

  use MarqueeWeb, :live_view

  alias Marquee.Podcasts
  alias MarqueeWeb.Components.ViewerComponents
  alias MarqueeWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:organization]

    shows =
      if org do
        %{results: shows} = Podcasts.list_shows(org, published: true, per_page: 100)
        shows
      else
        []
      end

    {:ok,
     socket
     |> assign(:page_title, "Podcasts")
     |> assign(:shows, shows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/podcasts"
      theme={@theme}
      theme_preview={@theme_preview}
      flash={@flash}
    >
      <div class="sv-page-content">
        <div class="sv-page-header">
          <h1 class="sv-page-title">Podcasts</h1>
        </div>

        <ViewerComponents.empty_state
          :if={@shows == []}
          title="No podcasts yet"
          description="Check back soon for new shows."
          icon="hero-microphone"
        />

        <div :if={@shows != []} class="sv-podcast-grid" data-test="sv-podcast-grid">
          <.link
            :for={show <- @shows}
            navigate={~p"/podcasts/#{show.slug}"}
            class="sv-podcast-card"
            data-test="sv-podcast-card"
          >
            <div class="sv-podcast-cover">
              <img :if={show.cover_artwork_url} src={show.cover_artwork_url} alt={show.title} />
              <div :if={!show.cover_artwork_url} class="sv-podcast-cover-placeholder">
                <.icon name="hero-microphone" class="w-12 h-12" />
              </div>
            </div>
            <div class="sv-podcast-card-body">
              <div class="sv-podcast-card-title">{show.title}</div>
              <div :if={show.author} class="sv-podcast-card-author">{show.author}</div>
              <div :if={show.description} class="sv-podcast-card-desc">{show.description}</div>
            </div>
          </.link>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
