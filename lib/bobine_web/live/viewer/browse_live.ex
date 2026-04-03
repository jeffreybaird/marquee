defmodule BobineWeb.Viewer.BrowseLive do
  use BobineWeb, :live_view

  alias Bobine.Content
  alias BobineWeb.Components.ViewerComponents
  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:organization]

    if org do
      %{results: videos} = Content.list_videos(org, per_page: 100)
      %{results: collections} = Content.list_collections(org, per_page: 100)
      %{results: tags} = Content.list_tags(org, per_page: 100)

      {:ok,
       socket
       |> assign(:page_title, "Browse")
       |> assign(:videos, videos)
       |> assign(:all_videos, videos)
       |> assign(:collections, collections)
       |> assign(:tags, tags)
       |> assign(:search, "")
       |> assign(:filter_collection, "")
       |> assign(:filter_tag, "")
       |> assign(:sort, "newest")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Browse")
       |> assign(:videos, [])
       |> assign(:all_videos, [])
       |> assign(:collections, [])
       |> assign(:tags, [])
       |> assign(:search, "")
       |> assign(:filter_collection, "")
       |> assign(:filter_tag, "")
       |> assign(:sort, "newest")}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    org = socket.assigns[:organization]
    search = Map.get(params, "search", "")
    sort = Map.get(params, "sort", "newest")
    filter_collection = Map.get(params, "collection", "")
    filter_tag = Map.get(params, "tag", "")

    opts = build_filter_opts(search, sort)

    %{results: videos} =
      if org do
        Content.list_videos(org, opts)
      else
        %{results: []}
      end

    videos = apply_client_filters(videos, filter_collection, filter_tag)

    {:noreply,
     socket
     |> assign(:videos, videos)
     |> assign(:search, search)
     |> assign(:sort, sort)
     |> assign(:filter_collection, filter_collection)
     |> assign(:filter_tag, filter_tag)}
  end

  defp build_filter_opts(search, sort) do
    opts = [per_page: 100]

    opts =
      if search != "" do
        Keyword.put(opts, :search, search)
      else
        opts
      end

    order =
      case sort do
        "oldest" -> :oldest
        "alphabetical" -> :alphabetical
        _ -> :newest
      end

    Keyword.put(opts, :order, order)
  end

  defp apply_client_filters(videos, _collection_id, _tag_id), do: videos

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/browse"
      theme={@theme}
      flash={@flash}
    >
      <div class="sv-page-content">
        <div class="sv-page-header">
          <h1 class="sv-page-title">Browse</h1>
        </div>

        <%!-- Filter bar --%>
        <form phx-change="filter" class="sv-filter-bar" data-test="sv-filter-bar">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Search videos..."
            class="sv-search-input"
            phx-debounce="300"
            data-test="sv-search-input"
          />

          <select
            :if={@collections != []}
            name="collection"
            class="sv-filter-select"
            data-test="sv-filter-collection"
          >
            <option value="">All collections</option>
            <option
              :for={c <- @collections}
              value={c.id}
              selected={@filter_collection == c.id}
            >
              {c.title}
            </option>
          </select>

          <select
            :if={@tags != []}
            name="tag"
            class="sv-filter-select"
            data-test="sv-filter-tag"
          >
            <option value="">All tags</option>
            <option :for={t <- @tags} value={t.id} selected={@filter_tag == t.id}>
              {t.name}
            </option>
          </select>

          <select name="sort" class="sv-filter-select" data-test="sv-filter-sort">
            <option value="newest" selected={@sort == "newest"}>Newest</option>
            <option value="oldest" selected={@sort == "oldest"}>Oldest</option>
            <option value="alphabetical" selected={@sort == "alphabetical"}>A-Z</option>
          </select>
        </form>

        <ViewerComponents.empty_state
          :if={@videos == []}
          title="No videos found"
          description="Try adjusting your filters or search terms."
          icon="hero-magnifying-glass"
        />

        <div :if={@videos != []} class="sv-browse-grid" data-test="sv-browse-grid">
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
