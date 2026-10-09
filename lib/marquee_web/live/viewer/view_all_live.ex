defmodule MarqueeWeb.Viewer.ViewAllLive do
  @moduledoc """
  View-all page for virtual collection sources (popular, recent).

  Renders a grid of videos matching the given source type, styled
  consistently with the collection page. Real collection rows link
  directly to CollectionLive instead.

  Hooks: CardFocus (via content_card)
  Events: card actions (via CardActions)
  Route: /browse/:source (viewer_public session, optional auth)
  """

  use MarqueeWeb, :live_view
  use MarqueeWeb.Viewer.CardActions

  alias Marquee.Content
  alias MarqueeWeb.Components.ViewerComponents
  alias MarqueeWeb.Components.ViewerLayout

  @valid_sources ~w(popular recent)

  @source_config %{
    "popular" => %{title: "Popular", order_by: [{:desc, :inserted_at}]},
    "recent" => %{title: "Recently Added", order_by: [{:desc, :inserted_at}]}
  }

  @impl true
  def mount(%{"source" => source}, _session, socket) when source in @valid_sources do
    org = socket.assigns[:organization]
    config = Map.fetch!(@source_config, source)

    %{results: videos} =
      Content.list_videos(org, per_page: 100, order_by: config.order_by)

    {:ok,
     socket
     |> assign(:page_title, config.title)
     |> assign(:source, source)
     |> assign(:source_title, config.title)
     |> assign(:videos, videos)}
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path={~p"/browse/#{@source}"}
      theme={@theme}
      theme_preview={@theme_preview}
      flash={@flash}
    >
      <div class="sv-collection-header" data-test="sv-view-all-header">
        <div class="sv-collection-info">
          <h1 class="sv-collection-title" data-test="sv-view-all-title">
            {@source_title}
          </h1>
        </div>
      </div>

      <div class="sv-page-content">
        <ViewerComponents.empty_state
          :if={@videos == []}
          title="No videos available"
          description="Check back later for new content."
        />

        <div :if={@videos != []} class="sv-browse-grid" data-test="sv-view-all-grid">
          <ViewerComponents.content_card
            :for={video <- @videos}
            video={video}
            size="grid"
            current_viewer={@current_viewer}
            favorited_ids={@favorited_ids}
            watchlisted_ids={@watchlisted_ids}
            queued_ids={@queued_ids}
          />
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
