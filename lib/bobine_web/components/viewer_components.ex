defmodule BobineWeb.Components.ViewerComponents do
  @moduledoc """
  Reusable components for viewer-facing streaming pages.

  All components use `--sv-*` CSS custom properties exclusively.
  No hardcoded colors. The org's theme provides the visual identity.
  """

  use BobineWeb, :html

  alias Bobine.Content
  alias Bobine.Content.{Season, Series, Video}

  # ---------------------------------------------------------------------------
  # Polymorphic Item Card — dispatches based on item type
  # ---------------------------------------------------------------------------

  attr :item, :any, required: true
  attr :progress, :float, default: nil
  attr :size, :string, values: ["row", "grid", "large"], default: "row"
  attr :current_viewer, :map, default: nil
  attr :card_id, :string, default: nil
  attr :favorited_ids, :any, default: MapSet.new()
  attr :watchlisted_ids, :any, default: MapSet.new()
  attr :queued_ids, :any, default: MapSet.new()

  @doc """
  Renders a card for a polymorphic catalog item — a video, series, or season.

  Use this from row renderers that may receive mixed content types. For
  callers that only ever pass videos, prefer `content_card/1` directly.
  """
  def content_item_card(%{item: %Series{}} = assigns) do
    ~H"""
    <.series_card
      series={@item}
      size={@size}
      card_id={@card_id}
    />
    """
  end

  def content_item_card(%{item: %Season{}} = assigns) do
    ~H"""
    <.season_card
      season={@item}
      size={@size}
      card_id={@card_id}
    />
    """
  end

  def content_item_card(%{item: %{type: type}} = assigns)
      when type in [:in_progress, :between_episodes, :next_season] do
    ~H"""
    <.continue_watching_card item={@item} card_id={@card_id} />
    """
  end

  def content_item_card(%{item: %Video{}} = assigns) do
    ~H"""
    <.content_card
      video={@item}
      progress={@progress}
      size={@size}
      current_viewer={@current_viewer}
      card_id={@card_id}
      favorited_ids={@favorited_ids}
      watchlisted_ids={@watchlisted_ids}
      queued_ids={@queued_ids}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Content Card
  # ---------------------------------------------------------------------------

  attr :video, :map, required: true
  attr :progress, :float, default: nil
  attr :size, :string, values: ["row", "grid", "large"], default: "row"
  attr :current_viewer, :map, default: nil
  attr :card_id, :string, default: nil
  attr :favorited_ids, :any, default: MapSet.new()
  attr :watchlisted_ids, :any, default: MapSet.new()
  attr :queued_ids, :any, default: MapSet.new()

  @doc """
  Renders a content card for a video with a hover/focus popup.

  When hovered or focused, a popup appears showing a video preview.
  Action buttons (favorite, watchlist, queue) are always visible
  inline with the video duration. Buttons reflect current engagement
  state via the `*_ids` MapSet attrs.

  ## Examples

      <.content_card video={@video} />
      <.content_card video={@video} progress={0.45} size="grid" current_viewer={@current_viewer} />

  """
  def content_card(assigns) do
    assigns =
      assign_new(assigns, :resolved_card_id, fn ->
        assigns[:card_id] || "card-#{assigns.video.id}"
      end)

    ~H"""
    <div
      id={@resolved_card_id}
      class={["sv-card-container", "sv-card-container-#{@size}"]}
      phx-hook="CardFocus"
      data-test={"sv-card-#{@video.id}"}
    >
      <div class={["sv-card", "sv-card-#{@size}"]}>
        <.link navigate={~p"/watch/#{@video.id}"} class="sv-card-thumb-link">
          <div class="sv-card-thumb">
            <img
              :if={@video.mux_playback_id}
              src={"https://image.mux.com/#{@video.mux_playback_id}/thumbnail.webp?width=640&height=360&fit_mode=smartcrop"}
              alt={@video.title}
              loading="lazy"
            />
            <div
              :if={@progress && @progress > 0}
              class="sv-card-progress"
              style={"width: #{min(@progress * 100, 100)}%"}
              data-test={"sv-card-progress-#{@video.id}"}
              aria-label={"#{round(@progress * 100)}% watched"}
            />
          </div>
        </.link>
        <div class="sv-card-info">
          <.link navigate={~p"/watch/#{@video.id}"} class="sv-card-title-link">
            <span class="sv-card-title">{@video.title}</span>
          </.link>
          <div class="sv-card-meta-row">
            <span :if={@video.duration} class="sv-card-meta">
              {format_duration(@video.duration)}
            </span>
            <div class="sv-card-actions">
              <button
                phx-click="card_toggle_favorite"
                phx-value-video-id={@video.id}
                class={["sv-card-action-btn", @video.id in @favorited_ids && "active"]}
                aria-label={"Favorite #{@video.title}"}
                aria-pressed={to_string(@video.id in @favorited_ids)}
                data-test={"sv-card-favorite-#{@video.id}"}
              >
                <.icon
                  name={if @video.id in @favorited_ids, do: "hero-heart-solid", else: "hero-heart"}
                  class="size-4"
                />
              </button>

              <button
                phx-click="card_add_to_watchlist"
                phx-value-video-id={@video.id}
                class={["sv-card-action-btn", @video.id in @watchlisted_ids && "active"]}
                aria-label={
                  if @video.id in @watchlisted_ids,
                    do: "#{@video.title} in watchlist",
                    else: "Add #{@video.title} to watchlist"
                }
                aria-pressed={to_string(@video.id in @watchlisted_ids)}
                data-test={"sv-card-watchlist-#{@video.id}"}
              >
                <.icon
                  name={
                    if @video.id in @watchlisted_ids, do: "hero-bookmark-solid", else: "hero-bookmark"
                  }
                  class="size-4"
                />
              </button>

              <button
                phx-click="card_add_to_queue"
                phx-value-video-id={@video.id}
                class={["sv-card-action-btn", @video.id in @queued_ids && "active"]}
                aria-label={
                  if @video.id in @queued_ids,
                    do: "#{@video.title} in queue",
                    else: "Add #{@video.title} to queue"
                }
                aria-pressed={to_string(@video.id in @queued_ids)}
                data-test={"sv-card-queue-#{@video.id}"}
              >
                <.icon
                  name={
                    if @video.id in @queued_ids, do: "hero-queue-list-solid", else: "hero-queue-list"
                  }
                  class="size-4"
                />
              </button>
            </div>
          </div>
        </div>
      </div>

      <div
        class="sv-card-popup"
        role="dialog"
        aria-label={"More about #{@video.title}"}
        data-test={"sv-card-popup-#{@video.id}"}
      >
        <div class="sv-card-popup-thumb" data-playback-id={@video.mux_playback_id}>
          <img
            :if={@video.mux_playback_id}
            src={"https://image.mux.com/#{@video.mux_playback_id}/thumbnail.webp?width=640&height=360&fit_mode=smartcrop"}
            alt=""
            aria-hidden="true"
          />
          <div
            :if={@progress && @progress > 0}
            class="sv-card-progress"
            style={"width: #{min(@progress * 100, 100)}%"}
            aria-hidden="true"
          />
          <div :if={Map.get(@video, :description)} class="sv-card-popup-body">
            <p class="sv-card-popup-desc">
              {truncate_description(Map.get(@video, :description), 120)}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Continue Watching Card
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true
  attr :card_id, :string, default: nil

  @doc """
  Renders a continue-watching card. The shape of the card is determined by
  the item's `:type` field:

    * `:in_progress` — episode/standalone with a progress bar
    * `:between_episodes` — next unwatched episode in a season (no bar)
    * `:next_season` — next season for a viewer who finished the previous one

  All variants reuse the standard `sv-card` shell so they sit alongside
  regular video cards in a row without visual drift.
  """
  def continue_watching_card(%{item: %{type: :next_season}} = assigns) do
    assigns =
      assigns
      |> assign_new(:resolved_card_id, fn ->
        assigns[:card_id] || "continue-card-season-#{assigns.item.season.id}"
      end)
      |> assign(:thumbnail_url, Content.resolve_season_thumbnail_cached(assigns.item.season))

    ~H"""
    <div
      id={@resolved_card_id}
      class="sv-card-container sv-card-container-row"
      data-test={"continue-card-season-#{@item.season.id}"}
    >
      <.link
        navigate={~p"/series/#{@item.series.slug}/season/#{@item.season.season_number}"}
        class="sv-card sv-card-row sv-continue-card"
      >
        <div class="sv-card-thumb">
          <img src={@thumbnail_url} alt={@item.season.title} loading="lazy" />
        </div>
        <div class="sv-card-info">
          <span class="sv-card-context">{@item.series.title} · New season</span>
          <span class="sv-card-title">{@item.season.title}</span>
          <div class="sv-card-meta-row">
            <span class="sv-card-meta">
              {@item.season.episode_count} {if @item.season.episode_count == 1,
                do: "Episode",
                else: "Episodes"}
            </span>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  def continue_watching_card(%{item: %{type: type}} = assigns)
      when type in [:in_progress, :between_episodes] do
    assigns =
      assigns
      |> assign_new(:resolved_card_id, fn ->
        assigns[:card_id] || "continue-card-#{assigns.item.video.id}"
      end)
      |> assign(:show_progress_bar?, type == :in_progress and assigns.item.duration > 0)
      |> assign(
        :progress_pct,
        progress_percent(assigns.item.position, assigns.item.duration)
      )
      |> assign(:remaining_seconds, assigns.item.duration - assigns.item.position)

    ~H"""
    <div
      id={@resolved_card_id}
      class="sv-card-container sv-card-container-row"
      data-test={"continue-card-#{@item.video.id}"}
    >
      <.link
        navigate={~p"/watch/#{@item.video.id}"}
        class="sv-card sv-card-row sv-continue-card"
      >
        <div class="sv-card-thumb">
          <img
            :if={@item.video.mux_playback_id}
            src={"https://image.mux.com/#{@item.video.mux_playback_id}/thumbnail.webp?width=640&height=360&fit_mode=smartcrop"}
            alt={@item.video.title}
            loading="lazy"
          />
          <div
            :if={@show_progress_bar?}
            class="sv-card-progress"
            style={"width: #{@progress_pct}%"}
            data-test={"continue-card-progress-#{@item.video.id}"}
          />
        </div>
        <div class="sv-card-info">
          <%= if @item.episode_context do %>
            <span class="sv-card-context" data-test={"continue-card-context-#{@item.video.id}"}>
              {@item.episode_context.series.title} · {@item.episode_context.season.title}
            </span>
            <span class="sv-card-title">
              S{@item.episode_context.season_number} E{@item.episode_context.episode_number} — {@item.video.title}
            </span>
            <div class="sv-card-meta-row">
              <span :if={@item.type == :in_progress} class="sv-card-meta">
                {format_remaining(@remaining_seconds)} remaining
              </span>
              <span :if={@item.type == :between_episodes} class="sv-card-meta">
                Up next
              </span>
            </div>
          <% else %>
            <span class="sv-card-title">{@item.video.title}</span>
            <div class="sv-card-meta-row">
              <span class="sv-card-meta">
                {format_remaining(@remaining_seconds)} remaining
              </span>
            </div>
          <% end %>
        </div>
      </.link>
    </div>
    """
  end

  defp progress_percent(position, duration) when is_number(position) and duration > 0 do
    percent = position / duration * 100
    min(percent, 100)
  end

  defp progress_percent(_position, _duration), do: 0

  defp format_remaining(seconds) when is_number(seconds) and seconds > 0 do
    minutes = div(trunc(seconds), 60)
    secs = rem(trunc(seconds), 60)

    if minutes >= 60 do
      hours = div(minutes, 60)
      mins = rem(minutes, 60)
      "#{hours}h #{mins}m"
    else
      "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
    end
  end

  defp format_remaining(_), do: "0:00"

  # ---------------------------------------------------------------------------
  # Series Card
  # ---------------------------------------------------------------------------

  attr :series, :map, required: true
  attr :size, :string, values: ["row", "grid", "large"], default: "row"
  attr :card_id, :string, default: nil

  @doc """
  Renders a card for a series. Shape and size match `content_card/1` so
  series and videos can sit next to each other in the same row.

  Thumbnail is resolved via `Bobine.Content.resolve_series_thumbnail_cached/1`
  (chain: series cover → latest season → first episode → placeholder). The
  card shows season count instead of duration and renders an optional
  "New Season" badge when `series.new_season` is true.

  ## Examples

      <.series_card series={@series} />
  """
  def series_card(assigns) do
    assigns =
      assigns
      |> assign_new(:resolved_card_id, fn ->
        assigns[:card_id] || "series-card-#{assigns.series.id}"
      end)
      |> assign(:thumbnail_url, Content.resolve_series_thumbnail_cached(assigns.series))
      |> assign(:season_count, series_season_count(assigns.series))
      |> assign(:show_new_season_badge?, Content.new_season_active?(assigns.series))

    ~H"""
    <div
      id={@resolved_card_id}
      class={["sv-card-container", "sv-card-container-#{@size}"]}
      data-test={"series-card-#{@series.id}"}
    >
      <.link navigate={~p"/series/#{@series.slug}"} class={["sv-card", "sv-card-#{@size}"]}>
        <div class="sv-card-thumb">
          <img src={@thumbnail_url} alt={@series.title} loading="lazy" />
          <span
            :if={@show_new_season_badge?}
            class="sv-card-badge sv-card-badge-new"
            data-test={"new-season-badge-#{@series.id}"}
          >
            New Season
          </span>
        </div>
        <div class="sv-card-info">
          <span class="sv-card-title">{@series.title}</span>
          <div class="sv-card-meta-row">
            <span class="sv-card-meta">
              {@season_count} {if @season_count == 1, do: "Season", else: "Seasons"}
            </span>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Season Card
  # ---------------------------------------------------------------------------

  attr :season, :map, required: true
  attr :size, :string, values: ["row", "grid", "large"], default: "row"
  attr :card_id, :string, default: nil

  @doc """
  Renders a card for a season. Same shape as `content_card/1` and
  `series_card/1`. Thumbnail resolves through season cover → first episode
  → placeholder. Metadata line shows the cached `episode_count`.

  Navigates to the parent series page; the underlying watch page will pick
  the right episode for the viewer.
  """
  def season_card(assigns) do
    assigns =
      assigns
      |> assign_new(:resolved_card_id, fn ->
        assigns[:card_id] || "season-card-#{assigns.season.id}"
      end)
      |> assign(:thumbnail_url, Content.resolve_season_thumbnail_cached(assigns.season))

    ~H"""
    <div
      id={@resolved_card_id}
      class={["sv-card-container", "sv-card-container-#{@size}"]}
      data-test={"season-card-#{@season.id}"}
    >
      <.link
        navigate={~p"/series/#{@season.series.slug}/season/#{@season.season_number}"}
        class={["sv-card", "sv-card-#{@size}"]}
      >
        <div class="sv-card-thumb">
          <img src={@thumbnail_url} alt={@season.title} loading="lazy" />
        </div>
        <div class="sv-card-info">
          <span class="sv-card-title">{@season.title}</span>
          <div class="sv-card-meta-row">
            <span class="sv-card-meta">
              {@season.episode_count} {if @season.episode_count == 1, do: "Episode", else: "Episodes"}
            </span>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  defp series_season_count(%Series{seasons: seasons}) when is_list(seasons), do: length(seasons)

  defp series_season_count(%Series{id: id}) do
    import Ecto.Query, warn: false

    Bobine.Content.Season
    |> where(series_id: ^id)
    |> where([s], is_nil(s.deleted_at))
    |> Bobine.Repo.aggregate(:count)
  end

  # ---------------------------------------------------------------------------
  # Content Row
  # ---------------------------------------------------------------------------

  attr :row, :map, required: true
  attr :videos, :list, required: true
  attr :progress_map, :map, default: %{}

  @doc """
  Renders a horizontal scrolling content row.

  ## Examples

      <.content_row row={@row} videos={@videos} />

  """
  def content_row(assigns) do
    ~H"""
    <section
      class="sv-row"
      id={"row-#{@row.id}"}
      phx-hook="RowScroller"
      data-test={"sv-row-#{@row.id}"}
    >
      <h2 class="sv-row-title">{@row.title}</h2>
      <div class="sv-row-scroll-wrapper">
        <button
          class="sv-row-arrow sv-row-arrow-left row-arrow-hidden"
          aria-label={"Scroll #{@row.title} left"}
          data-test={"row-arrow-prev-#{@row.id}"}
        >
          <.icon name="hero-chevron-left" class="size-5" aria-hidden="true" />
        </button>
        <div class="sv-row-scroll content-row-items">
          <.content_card
            :for={video <- @videos}
            video={video}
            progress={Map.get(@progress_map, video.id)}
            size="row"
          />
        </div>
        <button
          class="sv-row-arrow sv-row-arrow-right"
          aria-label={"Scroll #{@row.title} right"}
          data-test={"row-arrow-next-#{@row.id}"}
        >
          <.icon name="hero-chevron-right" class="size-5" aria-hidden="true" />
        </button>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Empty State
  # ---------------------------------------------------------------------------

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :icon, :string, default: "hero-film"
  slot :inner_block

  @doc """
  Renders an empty state placeholder.

  ## Examples

      <.empty_state title="Your watchlist is empty" description="Browse content to add videos." />

  """
  def empty_state(assigns) do
    ~H"""
    <div class="sv-empty-state" data-test="sv-empty-state">
      <div class="sv-empty-state-icon" aria-hidden="true">
        <.icon name={@icon} class="size-12" />
      </div>
      <h3 class="sv-empty-state-title">{@title}</h3>
      <p :if={@description} class="sv-empty-state-desc">{@description}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Badge / Tag Pill
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :variant, :string, values: ["default", "accent"], default: "default"

  @doc """
  Renders a small metadata badge.

  ## Examples

      <.badge label="HD" />
      <.badge label="New" variant="accent" />

  """
  def badge(assigns) do
    ~H"""
    <span class={["sv-badge", @variant == "accent" && "sv-badge-accent"]}>
      {@label}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Subscription Gate Overlay
  # ---------------------------------------------------------------------------

  attr :organization, :map, required: true
  slot :inner_block, required: true

  @doc """
  Renders a subscription gate overlay over content.

  ## Examples

      <.gate_overlay organization={@organization}>
        <p>Content preview</p>
      </.gate_overlay>

  """
  def gate_overlay(assigns) do
    ~H"""
    <div class="sv-gate-overlay" data-test="sv-gate-overlay">
      {render_slot(@inner_block)}
      <div class="sv-gate-gradient" aria-hidden="true" />
      <div class="sv-gate-cta">
        <h3 class="sv-gate-cta-title">Subscribe to watch</h3>
        <p class="sv-gate-cta-desc">
          Get access to all content on {@organization.name}.
        </p>
        <.link navigate="/subscribe" class="sv-btn sv-btn-accent">
          View plans
        </.link>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Skeleton Loaders
  # ---------------------------------------------------------------------------

  attr :count, :integer, default: 6

  @doc """
  Renders skeleton card placeholders for loading states.

  ## Examples

      <.skeleton_row count={4} />

  """
  def skeleton_row(assigns) do
    ~H"""
    <div class="sv-row">
      <div class="sv-skeleton sv-skeleton-title" />
      <div class="sv-row-scroll">
        <div :for={_i <- 1..@count} class="sv-skeleton sv-skeleton-card">
          <div class="sv-skeleton sv-skeleton-thumb" />
          <div class="sv-skeleton sv-skeleton-text" />
          <div class="sv-skeleton sv-skeleton-text-sm" />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Video Player Container
  # ---------------------------------------------------------------------------

  attr :video, :map, required: true
  attr :resume_position, :float, default: 0.0

  @doc """
  Renders the Mux Player container with themed controls.

  ## Examples

      <.video_player video={@video} resume_position={30.0} />

  """
  def video_player(assigns) do
    ~H"""
    <div
      id="player-container"
      phx-hook="MuxPlayer"
      data-playback-id={@video.mux_playback_id}
      data-video-id={@video.id}
      data-resume-position={@resume_position}
      class="sv-player-container"
      data-test="sv-player"
    >
      <mux-player
        stream-type="on-demand"
        playback-id={@video.mux_playback_id}
        metadata-video-title={@video.title}
        autoplay
        data-test="mux-player"
      >
      </mux-player>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Buttons
  # ---------------------------------------------------------------------------

  attr :rest, :global

  slot :inner_block, required: true

  @doc """
  Renders a primary accent button.

  ## Examples

      <.sv_button>Watch now</.sv_button>

  """
  def sv_button(assigns) do
    ~H"""
    <button class="sv-btn sv-btn-accent" {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp format_duration(nil), do: nil

  defp format_duration(seconds) when is_number(seconds) do
    minutes = div(trunc(seconds), 60)
    secs = rem(trunc(seconds), 60)

    if minutes >= 60 do
      hours = div(minutes, 60)
      mins = rem(minutes, 60)
      "#{hours}h #{mins}m"
    else
      "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
    end
  end

  defp format_duration(_), do: nil

  defp truncate_description(nil, _max), do: nil
  defp truncate_description("", _max), do: nil

  defp truncate_description(text, max) when byte_size(text) <= max, do: text

  defp truncate_description(text, max) do
    text
    |> String.slice(0, max)
    |> String.trim_trailing()
    |> Kernel.<>("...")
  end
end
