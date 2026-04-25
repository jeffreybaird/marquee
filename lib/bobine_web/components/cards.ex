defmodule BobineWeb.Components.Cards do
  @moduledoc """
  Card variants for the viewer-facing brand system.

  Six atomic card components, each with a matching skeleton. Cards are
  presentational — they accept plain maps with the fields they need and
  render without any DB or context access.

  Every card uses semantic token classes defined by the brand system
  (see `.claude/brand-system.md`). No hardcoded colors. Aspect ratios
  are enforced on the image container only; the card's layout footprint
  never changes on hover.
  """

  use BobineWeb, :html

  # ---------------------------------------------------------------------------
  # 1. Poster Portrait — 2:3
  # ---------------------------------------------------------------------------

  attr :item, :map,
    required: true,
    doc:
      "Map with :id, :title, :image_url, :year, :duration, :rating, and optional :progress (0.0–1.0)"

  attr :href, :string, default: "#"
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  def poster_portrait(assigns) do
    ~H"""
    <a
      href={@href}
      data-test={"card-poster-#{@item.id}"}
      class={[
        "group relative block overflow-hidden rounded-md bg-surface",
        "border border-border-subtle",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      ]}
    >
      <div class="relative aspect-[2/3] w-full overflow-hidden">
        <img
          src={@item.image_url}
          alt={@item.title}
          loading="lazy"
          class="h-full w-full object-cover"
        />

        <%!-- Hover metadata overlay (only when details bar is shown; if the
             details bar is already hidden, the always-on title overlay takes
             over and the hover overlay would compete with it). --%>
        <div
          :if={@show_details}
          class={[
            "absolute inset-0 flex flex-col justify-end",
            "bg-gradient-to-t from-bg/95 via-bg/40 to-transparent",
            "opacity-0 transition-opacity duration-200 ease-out",
            "group-hover:opacity-100 group-focus-within:opacity-100"
          ]}
        >
          <div class="p-3">
            <h3 class="font-display text-lg leading-tight tracking-tight text-text-primary">
              {@item.title}
            </h3>
            <p class="mt-1 font-mono text-xs text-text-muted">
              {@item.year} · {@item.duration}
            </p>
          </div>
        </div>

        <%!-- Always-on title overlay (details bar hidden + overlay requested). --%>
        <div
          :if={!@show_details && @title_overlay}
          class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-bg/90 via-bg/50 to-transparent p-3"
          data-test={"card-poster-title-overlay-#{@item.id}"}
        >
          <h3 class="font-display text-base leading-tight tracking-tight text-text-primary">
            {@item.title}
          </h3>
        </div>

        <div
          :if={@item[:progress]}
          class="absolute inset-x-4 bottom-5 h-1 overflow-hidden rounded-full bg-black/60"
        >
          <div
            class="h-full rounded-full bg-white"
            style={"width: #{round(@item.progress * 100)}%"}
          />
        </div>
      </div>
    </a>
    """
  end

  @doc """
  Skeleton for `poster_portrait/1`. Matches outer dimensions (2:3).
  """
  def poster_portrait_skeleton(assigns) do
    ~H"""
    <div
      data-test="card-poster-skeleton"
      class="relative aspect-[2/3] w-full overflow-hidden rounded-md bg-surface border border-border-subtle"
    >
      <.shimmer />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # 2. Landscape Episode — 16:9
  # ---------------------------------------------------------------------------

  attr :item, :map,
    required: true,
    doc:
      "Map with :id, :title, :series, :image_url, :episode_number, :duration, optional :progress"

  attr :href, :string, default: "#"
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  def landscape_episode(assigns) do
    ~H"""
    <a
      href={@href}
      data-test={"card-episode-#{@item.id}"}
      class={[
        "group block overflow-hidden rounded-md",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      ]}
    >
      <div class="relative aspect-video w-full overflow-hidden rounded-md bg-surface border border-border-subtle">
        <img
          src={@item.image_url}
          alt={@item.title}
          loading="lazy"
          class="h-full w-full object-cover"
        />

        <span class={[
          "absolute left-2 top-2 rounded-sm bg-overlay/90 px-2 py-0.5",
          "font-mono text-xs text-text-primary"
        ]}>
          EP {@item.episode_number}
        </span>

        <span class={[
          "absolute right-2 top-2 rounded-sm bg-overlay/90 px-2 py-0.5",
          "font-mono text-xs text-text-primary"
        ]}>
          {@item.duration}
        </span>

        <div class={[
          "absolute inset-0 flex items-center justify-center",
          "bg-bg/40 opacity-0 transition-opacity duration-200 ease-out",
          "group-hover:opacity-100 group-focus-within:opacity-100"
        ]}>
          <span class={[
            "flex h-12 w-12 items-center justify-center rounded-full",
            "bg-accent text-accent-text"
          ]}>
            <.icon name="hero-play-solid" class="h-6 w-6" />
          </span>
        </div>

        <div
          :if={!@show_details && @title_overlay}
          class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-bg/90 via-bg/50 to-transparent p-3 pr-16"
          data-test={"card-episode-title-overlay-#{@item.id}"}
        >
          <h3 class="font-display text-base leading-tight tracking-tight text-text-primary">
            {@item.title}
          </h3>
        </div>

        <div
          :if={@item[:progress]}
          class="absolute inset-x-4 bottom-5 h-1 overflow-hidden rounded-full bg-black/60"
        >
          <div
            class="h-full rounded-full bg-white"
            style={"width: #{round(@item.progress * 100)}%"}
          />
        </div>
      </div>

      <div :if={@show_details} class="mt-3 space-y-1">
        <h3 class="font-display text-base leading-tight tracking-tight text-text-primary">
          {@item.title}
        </h3>
        <p class="font-ui text-sm text-text-secondary">
          {@item.series}
        </p>
      </div>
    </a>
    """
  end

  def landscape_episode_skeleton(assigns) do
    ~H"""
    <div data-test="card-episode-skeleton" class="block">
      <div class="relative aspect-video w-full overflow-hidden rounded-md bg-surface border border-border-subtle">
        <.shimmer />
      </div>
      <div class="mt-3 space-y-2">
        <div class="h-4 w-3/4 rounded bg-surface overflow-hidden relative">
          <.shimmer />
        </div>
        <div class="h-3 w-1/2 rounded bg-surface overflow-hidden relative">
          <.shimmer />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # 3. Creator Identity — 1:1
  # ---------------------------------------------------------------------------

  attr :item, :map,
    required: true,
    doc: "Map with :id, :name, :image_url, :content_count"

  attr :href, :string, default: "#"
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  def creator_identity(assigns) do
    ~H"""
    <a
      href={@href}
      data-test={"card-creator-#{@item.id}"}
      class={[
        "group block",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent rounded-md"
      ]}
    >
      <div class="relative aspect-square w-full overflow-hidden rounded-md bg-surface border border-border-subtle">
        <img
          src={@item.image_url}
          alt={@item.name}
          loading="lazy"
          class="h-full w-full object-cover"
        />

        <div class={[
          "absolute inset-0 flex items-center justify-center bg-bg/50",
          "opacity-0 transition-opacity duration-200 ease-out",
          "group-hover:opacity-100 group-focus-within:opacity-100"
        ]}>
          <span class={[
            "rounded-full bg-accent px-4 py-1.5",
            "font-ui text-sm text-accent-text"
          ]}>
            View channel
          </span>
        </div>

        <div
          :if={!@show_details && @title_overlay}
          class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-bg/90 via-bg/50 to-transparent p-3 text-center"
          data-test={"card-creator-title-overlay-#{@item.id}"}
        >
          <h3 class="font-display text-base leading-tight tracking-tight text-text-primary">
            {@item.name}
          </h3>
        </div>
      </div>

      <div :if={@show_details} class="mt-3 text-center">
        <h3 class="font-display text-base leading-tight tracking-tight text-text-primary">
          {@item.name}
        </h3>
        <p class="mt-0.5 font-mono text-xs text-text-muted">
          {@item.content_count} titles
        </p>
      </div>
    </a>
    """
  end

  def creator_identity_skeleton(assigns) do
    ~H"""
    <div data-test="card-creator-skeleton" class="block">
      <div class="relative aspect-square w-full overflow-hidden rounded-md bg-surface border border-border-subtle">
        <.shimmer />
      </div>
      <div class="mt-3 flex flex-col items-center gap-2">
        <div class="relative h-4 w-2/3 overflow-hidden rounded bg-surface">
          <.shimmer />
        </div>
        <div class="relative h-3 w-1/3 overflow-hidden rounded bg-surface">
          <.shimmer />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # 4. Collection Editorial — 3:2
  # ---------------------------------------------------------------------------

  attr :item, :map,
    required: true,
    doc: "Map with :id, :title, :image_url, :film_count, :curator_note"

  attr :href, :string, default: "#"
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  def collection_editorial(assigns) do
    ~H"""
    <a
      href={@href}
      data-test={"card-collection-#{@item.id}"}
      class={[
        "group relative block overflow-hidden rounded-md bg-surface",
        "border border-border-subtle",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      ]}
    >
      <div class="relative aspect-[3/2] w-full overflow-hidden">
        <img
          src={@item.image_url}
          alt={@item.title}
          loading="lazy"
          class="h-full w-full object-cover"
        />

        <%!-- Details always live on top of the image for this variant. When
             :show_details is false we still show the title if :title_overlay
             is true, but suppress the film count and curator note. --%>
        <div
          :if={@show_details || @title_overlay}
          class="absolute inset-x-0 bottom-0 h-2/3 bg-gradient-to-t from-bg/95 via-bg/60 to-transparent"
        />

        <div
          :if={@show_details}
          class="absolute inset-x-0 bottom-0 p-4"
        >
          <p class="font-mono text-xs uppercase tracking-wide text-text-muted">
            {@item.film_count} films
          </p>
          <h3 class="mt-1 font-display text-2xl leading-tight tracking-tight text-text-primary">
            {@item.title}
          </h3>
          <p class={[
            "mt-2 max-h-0 overflow-hidden font-body text-sm leading-relaxed text-text-secondary",
            "transition-all duration-300 ease-out",
            "group-hover:max-h-24 group-focus-within:max-h-24"
          ]}>
            {@item.curator_note}
          </p>
        </div>

        <div
          :if={!@show_details && @title_overlay}
          class="absolute inset-x-0 bottom-0 p-4"
          data-test={"card-collection-title-overlay-#{@item.id}"}
        >
          <h3 class="font-display text-2xl leading-tight tracking-tight text-text-primary">
            {@item.title}
          </h3>
        </div>
      </div>
    </a>
    """
  end

  def collection_editorial_skeleton(assigns) do
    ~H"""
    <div
      data-test="card-collection-skeleton"
      class="relative aspect-[3/2] w-full overflow-hidden rounded-md bg-surface border border-border-subtle"
    >
      <.shimmer />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # 5. Progress Course — 16:9 + metadata
  # ---------------------------------------------------------------------------

  attr :item, :map,
    required: true,
    doc:
      "Map with :id, :title, :instructor, :image_url, :lessons_completed, :lessons_total, :percent (0–100)"

  attr :href, :string, default: "#"
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  def progress_course(assigns) do
    complete? = assigns.item.percent >= 100
    assigns = assign(assigns, :complete?, complete?)

    ~H"""
    <a
      href={@href}
      data-test={"card-course-#{@item.id}"}
      class={[
        "group block overflow-hidden rounded-md",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      ]}
    >
      <div class="relative aspect-video w-full overflow-hidden rounded-md bg-surface border border-border-subtle">
        <img
          src={@item.image_url}
          alt={@item.title}
          loading="lazy"
          class="h-full w-full object-cover"
        />

        <span class={[
          "absolute right-2 top-2 rounded-full px-2.5 py-0.5",
          "font-mono text-xs",
          if(@complete?,
            do: "bg-success text-accent-text",
            else: "bg-overlay/90 text-text-primary"
          )
        ]}>
          {@item.percent}%
        </span>

        <div class={[
          "absolute inset-0 flex items-center justify-center bg-bg/40",
          "opacity-0 transition-opacity duration-200 ease-out",
          "group-hover:opacity-100 group-focus-within:opacity-100"
        ]}>
          <span class="flex h-12 w-12 items-center justify-center rounded-full bg-accent text-accent-text">
            <.icon name="hero-play-solid" class="h-6 w-6" />
          </span>
        </div>

        <div
          :if={!@show_details && @title_overlay}
          class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-bg/90 via-bg/50 to-transparent p-3"
          data-test={"card-course-title-overlay-#{@item.id}"}
        >
          <h3 class="font-display text-base leading-tight tracking-tight text-text-primary">
            {@item.title}
          </h3>
        </div>

        <%!-- Watch-progress bar overlaid on the thumbnail. Inset from the
             card edges and rounded so it reads as its own UI element rather
             than blending into the bottom border. Stays visible when the
             details panel below is hidden, so a "Continue Watching" row
             always communicates how far through the user is. --%>
        <div
          :if={@item.percent > 0}
          class="absolute inset-x-4 bottom-5 h-1 overflow-hidden rounded-full bg-black/60"
          role="progressbar"
          aria-valuenow={@item.percent}
          aria-valuemin="0"
          aria-valuemax="100"
          aria-label={"Course progress: #{@item.percent} percent"}
          data-test={"card-course-progress-#{@item.id}"}
        >
          <div
            class={[
              "h-full rounded-full",
              if(@complete?, do: "bg-success", else: "bg-white")
            ]}
            style={"width: #{@item.percent}%"}
          />
        </div>
      </div>

      <div :if={@show_details} class="mt-3 space-y-1.5">
        <h3 class="font-display text-base leading-tight tracking-tight text-text-primary">
          {@item.title}
        </h3>
        <p class="font-ui text-sm text-text-secondary">
          {@item.instructor}
        </p>
        <p class="font-mono text-xs text-text-muted">
          Lesson {@item.lessons_completed} of {@item.lessons_total}
        </p>
      </div>
    </a>
    """
  end

  def progress_course_skeleton(assigns) do
    ~H"""
    <div data-test="card-course-skeleton" class="block">
      <div class="relative aspect-video w-full overflow-hidden rounded-md bg-surface border border-border-subtle">
        <.shimmer />
      </div>
      <div class="mt-3 space-y-2">
        <div class="relative h-4 w-3/4 overflow-hidden rounded bg-surface">
          <.shimmer />
        </div>
        <div class="relative h-3 w-1/2 overflow-hidden rounded bg-surface">
          <.shimmer />
        </div>
        <div class="relative h-3 w-1/3 overflow-hidden rounded bg-surface">
          <.shimmer />
        </div>
        <div class="relative mt-2 h-1.5 w-full overflow-hidden rounded-full bg-elevated">
          <.shimmer />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # 6. Minimal List Item — horizontal
  # ---------------------------------------------------------------------------

  attr :item, :map,
    required: true,
    doc: "Map with :id, :title, :image_url, :metadata, :synopsis"

  attr :href, :string, default: "#"
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  @doc """
  Horizontal thumbnail + metadata layout. When `show_details` is false,
  the right-hand metadata column is suppressed and only the poster thumb
  renders; the thumb grows to fit the available width and the title sits
  on an overlay when `title_overlay` is true.
  """
  def minimal_list_item(assigns) do
    ~H"""
    <a
      href={@href}
      data-test={"card-list-#{@item.id}"}
      class={[
        "group flex items-center gap-4 rounded-md p-3",
        "transition-colors duration-150 ease-out",
        "hover:bg-surface focus-visible:bg-surface",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      ]}
    >
      <div class={[
        "relative flex-shrink-0 overflow-hidden rounded bg-surface border border-border-subtle",
        if(@show_details, do: "h-20 w-[3.333rem]", else: "h-24 w-full")
      ]}>
        <img
          src={@item.image_url}
          alt={@item.title}
          loading="lazy"
          class="h-full w-full object-cover"
        />
        <div
          :if={!@show_details && @title_overlay}
          class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-bg/90 via-bg/50 to-transparent p-2"
          data-test={"card-list-title-overlay-#{@item.id}"}
        >
          <h3 class="font-display text-sm leading-tight tracking-tight text-text-primary">
            {@item.title}
          </h3>
        </div>
      </div>

      <div :if={@show_details} class="min-w-0 flex-1">
        <h3 class="font-display text-base leading-tight tracking-tight text-text-primary">
          {@item.title}
        </h3>
        <p class="mt-0.5 font-mono text-xs text-text-muted">
          {@item.metadata}
        </p>
        <p class="mt-1 line-clamp-2 font-body text-sm leading-relaxed text-text-secondary">
          {@item.synopsis}
        </p>
      </div>

      <span
        :if={@show_details}
        class={[
          "flex-shrink-0 text-text-muted opacity-0 transition-opacity duration-150",
          "group-hover:opacity-100 group-focus-within:opacity-100"
        ]}
      >
        <.icon name="hero-chevron-right" class="h-5 w-5" />
      </span>
    </a>
    """
  end

  def minimal_list_item_skeleton(assigns) do
    ~H"""
    <div data-test="card-list-skeleton" class="flex items-center gap-4 p-3">
      <div class="relative h-20 w-[3.333rem] flex-shrink-0 overflow-hidden rounded bg-surface border border-border-subtle">
        <.shimmer />
      </div>
      <div class="min-w-0 flex-1 space-y-2">
        <div class="relative h-4 w-2/3 overflow-hidden rounded bg-surface">
          <.shimmer />
        </div>
        <div class="relative h-3 w-1/3 overflow-hidden rounded bg-surface">
          <.shimmer />
        </div>
        <div class="relative h-3 w-full overflow-hidden rounded bg-surface">
          <.shimmer />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Shimmer — shared sweep overlay
  # ---------------------------------------------------------------------------

  @doc """
  Shimmer sweep overlay. Absolute-positioned inside a relatively-positioned
  skeleton container. Uses the `shimmer` keyframe defined in app.css.
  """
  def shimmer(assigns) do
    ~H"""
    <div
      aria-hidden="true"
      class={[
        "pointer-events-none absolute inset-0",
        "bg-gradient-to-r from-transparent via-white/[0.04] to-transparent",
        "animate-[shimmer_1.5s_ease-in-out_infinite]"
      ]}
    />
    """
  end
end
