defmodule MarqueeWeb.Viewer.CollectionLive do
  @moduledoc """
  Single collection page showing the collection title/description and its
  videos in a grid layout.

  Hooks: CardFocus (via content_card)
  Events: card actions (via CardActions)
  Route: /collections/:slug (viewer_public session, optional auth)
  """

  use MarqueeWeb, :live_view
  use MarqueeWeb.Viewer.CardActions

  alias Marquee.Content
  alias MarqueeWeb.Components.ViewerComponents
  alias MarqueeWeb.Components.ViewerLayout

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    org = socket.assigns[:organization]

    case Content.get_collection_by_slug(org, slug) do
      {:ok, collection} ->
        %{results: videos} = Content.list_collection_videos(org, collection, per_page: 100)

        {:ok,
         socket
         |> assign(:page_title, collection.title)
         |> assign(:collection, collection)
         |> assign(:videos, videos)}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path={~p"/collections/#{@collection.slug}"}
      theme={@theme}
      theme_preview={@theme_preview}
      flash={@flash}
    >
      <%!-- Collection header --%>
      <div class="sv-collection-header" data-test="sv-collection-header">
        <div :if={@collection.cover_image_url} class="sv-collection-cover">
          <img src={@collection.cover_image_url} alt="" />
        </div>
        <div class="sv-collection-info">
          <h1 class="sv-collection-title" data-test="sv-collection-title">
            {@collection.title}
          </h1>
          <p :if={@collection.description} class="sv-collection-desc">
            {@collection.description}
          </p>
          <.link
            :if={@videos != []}
            navigate={~p"/watch/#{List.first(@videos).id}"}
            class="sv-btn sv-btn-accent"
            data-test="sv-collection-play-first"
          >
            <.icon name="hero-play" class="size-5 mr-2" aria-hidden="true" /> Play first
          </.link>
        </div>
      </div>

      <%!-- Videos grid --%>
      <div class="sv-page-content">
        <ViewerComponents.empty_state
          :if={@videos == []}
          title="No videos in this collection"
          description="Check back later for new content."
        />

        <div :if={@videos != []} class="sv-browse-grid" data-test="sv-collection-grid">
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
