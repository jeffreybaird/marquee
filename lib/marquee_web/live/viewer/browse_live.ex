defmodule MarqueeWeb.Viewer.BrowseLive do
  @moduledoc """
  Browse/search page for viewer-facing content. Supports text search,
  collection and tag filtering, and sort (newest/oldest/a-z/z-a).

  Hooks: CardFocus (via content_card)
  Events: search, filter, sort, card actions (via CardActions)
  Route: /browse (viewer_public session, optional auth)
  """

  use MarqueeWeb, :live_view
  use MarqueeWeb.Viewer.CardActions

  alias Marquee.Content
  alias MarqueeWeb.Components.ViewerComponents
  alias MarqueeWeb.Components.ViewerLayout

  # Default page size for the browse grid. Overridable via
  # `config :marquee, :browse_per_page, <n>`. User-facing pagination UI is
  # out of scope for this module — callers that need more results should
  # raise the config, not bypass it.
  @default_per_page 24

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:organization]
    per_page = initial_page_size(org)

    if org do
      opts = demo_filter_opts([per_page: per_page], org, socket.assigns[:current_viewer])
      %{results: videos} = Content.list_videos(org, opts)
      %{results: tags} = Content.list_tags(org, per_page: per_page)

      {:ok,
       socket
       |> assign(:page_title, "Browse")
       |> assign(:videos, videos)
       |> assign(:all_videos, videos)
       |> assign(:tags, tags)
       |> assign(:search, "")
       |> assign(:filter_tag, "")
       |> assign(:sort, "newest")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Browse")
       |> assign(:videos, [])
       |> assign(:all_videos, [])
       |> assign(:tags, [])
       |> assign(:search, "")
       |> assign(:filter_tag, "")
       |> assign(:sort, "newest")}
    end
  end

  defp initial_page_size(%{demo_kind: :admin_sandbox}), do: 100

  defp initial_page_size(_org),
    do: Application.get_env(:marquee, :browse_per_page, @default_per_page)

  @impl true
  def handle_params(params, _uri, socket) do
    tag_id = Map.get(params, "tag", "")

    if tag_id != "" and tag_id != socket.assigns.filter_tag do
      {:noreply, apply_filters(socket, %{"tag" => tag_id})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, apply_filters(socket, params)}
  end

  defp apply_filters(socket, params) do
    org = socket.assigns[:organization]
    search = Map.get(params, "search", socket.assigns.search)
    sort = Map.get(params, "sort", socket.assigns.sort)
    filter_tag = Map.get(params, "tag", socket.assigns.filter_tag)

    videos = fetch_filtered_videos(org, search, sort, filter_tag, socket.assigns[:current_viewer])

    socket
    |> assign(:videos, videos)
    |> assign(:search, search)
    |> assign(:sort, sort)
    |> assign(:filter_tag, filter_tag)
  end

  defp fetch_filtered_videos(nil, _search, _sort, _tag, _viewer), do: []

  defp fetch_filtered_videos(org, search, sort, tag_id, viewer) do
    opts = build_filter_opts(search, sort) |> demo_filter_opts(org, viewer)

    if tag_id != "" do
      %{results: videos} = Content.list_videos_by_tag(org, %{id: tag_id}, opts)
      videos
    else
      %{results: videos} = Content.list_videos(org, opts)
      videos
    end
  end

  defp demo_filter_opts(opts, org, viewer) do
    ids = (org.features || %{})["subscriber_demo_video_ids"]

    if Marquee.SubscriberDemo.demo_viewer?(viewer) && is_list(ids),
      do: Keyword.put(opts, :video_ids, ids),
      else: opts
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

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/browse"
      theme={@theme}
      theme_preview={@theme_preview}
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
            current_viewer={@current_viewer}
            favorited_ids={@favorited_ids}
            watchlisted_ids={@watchlisted_ids}
            queued_ids={@queued_ids}
            preview_on_hover={true}
          />
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end
end
