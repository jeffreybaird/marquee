defmodule BobineWeb.Components.ViewerComponents do
  @moduledoc """
  Reusable components for viewer-facing streaming pages.

  All components use `--sv-*` CSS custom properties exclusively.
  No hardcoded colors. The org's theme provides the visual identity.
  """

  use BobineWeb, :html

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
