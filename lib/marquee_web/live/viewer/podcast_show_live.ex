defmodule MarqueeWeb.Viewer.PodcastShowLive do
  @moduledoc """
  Viewer-facing podcast show detail page. Displays show metadata, episode list,
  and a token-gated feed URL for subscribers who have access.

  Route: /podcasts/:slug (viewer_public session, optional auth)
  """

  use MarqueeWeb, :live_view

  alias Marquee.Podcasts
  alias MarqueeWeb.Components.ViewerComponents
  alias MarqueeWeb.Components.ViewerLayout

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    org = socket.assigns[:organization]
    viewer = socket.assigns[:current_viewer]

    case Podcasts.get_show_by_slug(org, slug) do
      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/podcasts")}

      {:ok, show} ->
        episodes = if show.published, do: Podcasts.list_published_episodes(show), else: []
        {has_access, feed_token} = resolve_access(show, viewer)

        {:ok,
         socket
         |> assign(:page_title, show.title)
         |> assign(:show, show)
         |> assign(:episodes, episodes)
         |> assign(:has_access, has_access)
         |> assign(:feed_token, feed_token)}
    end
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
      flash={@flash}
    >
      <div class="sv-page-content">
        <div class="sv-page-header" style="margin-bottom: 8px;">
          <.link
            navigate={~p"/podcasts"}
            style="font-size: 0.85rem; color: var(--sv-text-secondary); text-decoration: none;"
          >
            ← Podcasts
          </.link>
        </div>

        <%!-- Show header --%>
        <div class="sv-podcast-show-header">
          <div class="sv-podcast-show-cover">
            <img :if={@show.cover_artwork_url} src={@show.cover_artwork_url} alt={@show.title} />
            <.icon
              :if={!@show.cover_artwork_url}
              name="hero-microphone"
              class="w-16 h-16"
              style="color: var(--sv-text-secondary);"
            />
          </div>
          <div class="sv-podcast-show-meta">
            <h1 class="sv-podcast-show-title">{@show.title}</h1>
            <div :if={@show.author} class="sv-podcast-show-author">{@show.author}</div>
            <p :if={@show.description} class="sv-podcast-show-desc">{@show.description}</p>
            <div :if={@show.primary_category} class="sv-podcast-show-category">
              {@show.primary_category}
            </div>
          </div>
        </div>

        <%!-- Access box --%>
        <div class="sv-podcast-access-box" data-test="sv-podcast-access-box">
          <div :if={@has_access and @feed_token} data-test="sv-podcast-feed-section">
            <div class="sv-podcast-access-box-title">Your podcast feed</div>
            <p class="sv-podcast-access-box-desc">
              Copy this URL into any podcast app (Apple Podcasts, Overcast, Pocket Casts, etc.) to subscribe. Keep it private — this URL is unique to your account.
            </p>
            <div class="sv-podcast-feed-url">
              <input
                type="text"
                readonly
                value={feed_url(@feed_token)}
                aria-label="Podcast feed URL"
                data-test="sv-podcast-feed-url"
                phx-click={JS.dispatch("click", to: "#copy-feed-btn-#{@feed_token.id}")}
              />
              <button
                id={"copy-feed-btn-#{@feed_token.id}"}
                class="sv-button sv-button-sm"
                phx-click={JS.dispatch("copy", detail: %{text: feed_url(@feed_token)})}
                aria-label="Copy feed URL"
                type="button"
              >
                Copy
              </button>
            </div>
          </div>

          <div :if={!@has_access and @current_viewer} data-test="sv-podcast-subscribe-prompt">
            <div class="sv-podcast-access-box-title">Subscribe to listen</div>
            <p class="sv-podcast-access-box-desc">
              This podcast is available to active subscribers. Subscribe to get access and your personal feed URL.
            </p>
            <.link navigate={~p"/subscribe"} class="sv-button sv-button-primary">
              Subscribe
            </.link>
          </div>

          <div :if={!@current_viewer} data-test="sv-podcast-login-prompt">
            <div class="sv-podcast-access-box-title">Log in to listen</div>
            <p class="sv-podcast-access-box-desc">
              Log in or create an account to access this podcast.
            </p>
            <div style="display: flex; gap: 12px;">
              <.link navigate={~p"/login"} class="sv-button sv-button-primary">Log in</.link>
              <.link navigate={~p"/register"} class="sv-button">Sign up</.link>
            </div>
          </div>
        </div>

        <%!-- Episode list --%>
        <div data-test="sv-episode-list-section">
          <h2 class="sv-section-title" style="margin-bottom: 16px;">
            Episodes
            <span style="font-size: 0.85rem; font-weight: 400; color: var(--sv-text-secondary);">
              ({length(@episodes)})
            </span>
          </h2>

          <ViewerComponents.empty_state
            :if={@episodes == []}
            title="No episodes yet"
            description="Episodes will appear here once published."
            icon="hero-microphone"
          />

          <div :if={@episodes != []} class="sv-episode-list" data-test="sv-episode-list">
            <div
              :for={episode <- @episodes}
              class="sv-episode-item"
              data-test="sv-episode-item"
            >
              <div class="sv-episode-num" aria-hidden="true">
                {episode.episode_number || "·"}
              </div>
              <div class="sv-episode-body">
                <div class="sv-episode-title">{episode.title}</div>
                <p :if={episode.description} class="sv-episode-desc">
                  {episode.description}
                </p>
                <div class="sv-episode-meta">
                  <span :if={episode.publish_date}>
                    {format_publish_date(episode.publish_date)}
                  </span>
                  <span :if={episode.duration_seconds}>
                    {format_duration(episode.duration_seconds)}
                  </span>
                  <span
                    :if={episode.episode_type && episode.episode_type != "full"}
                    style="text-transform: capitalize;"
                  >
                    {episode.episode_type}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </ViewerLayout.viewer_layout>
    """
  end

  defp resolve_access(_show, nil), do: {false, nil}

  defp resolve_access(show, %{__preview__: true} = viewer),
    do: {Podcasts.can_access?(show, viewer), nil}

  defp resolve_access(show, viewer) do
    if Podcasts.can_access?(show, viewer) do
      case Podcasts.issue_feed_token(show, viewer) do
        {:ok, token} -> {true, token}
        _ -> {true, nil}
      end
    else
      {false, nil}
    end
  end

  defp feed_url(token) do
    MarqueeWeb.Endpoint.url() <> ~p"/podcasts/#{token.token}/feed.xml"
  end

  defp format_publish_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y")
  end

  defp format_publish_date(_), do: nil

  defp format_duration(nil), do: nil

  defp format_duration(secs) when is_integer(secs) do
    h = div(secs, 3600)
    m = secs |> rem(3600) |> div(60)
    s = rem(secs, 60)

    if h > 0 do
      "#{h}:#{pad2(m)}:#{pad2(s)}"
    else
      "#{m}:#{pad2(s)}"
    end
  end

  defp pad2(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
