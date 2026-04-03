defmodule BobineWeb.Viewer.CollectionLive do
  use BobineWeb, :live_view

  alias Bobine.Content
  alias BobineWeb.Components.ViewerLayout
  alias BobineWeb.Components.ViewerComponents

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
          />
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
