defmodule BobineWeb.Components.Rows do
  @moduledoc """
  Row components for the viewer-facing brand system.

  Rows are horizontal building blocks composed from card variants
  (see `BobineWeb.Components.Cards`). A page is an ordered list of rows.

  The `row/1` dispatcher lets a page render any row type by passing a
  row configuration map — no hardcoded case statement in the template.

  All rows that scroll use two LiveView hooks: `Carousel` (drag-to-scroll
  with momentum + arrow navigation) and `StaggerReveal` (entrance
  animation). Both registered in `assets/js/hooks/index.ts`.

  ## Absolute rules

    * Continue watching row never renders when `items` is empty.
    * Hero row uses its own layout, not a card component.
    * Arrow buttons appear on desktop hover only.
  """

  use BobineWeb, :html

  alias BobineWeb.Components.Cards

  # ---------------------------------------------------------------------------
  # Dispatcher
  # ---------------------------------------------------------------------------

  attr :row, :map,
    required: true,
    doc: "Row config map with :type atom and row-specific fields"

  @doc """
  Dispatches to the correct row component based on `row.type`.

  ## Supported types

  `:hero`, `:content`, `:continue_watching`, `:series`, `:creator_showcase`,
  `:editorial_spotlight`.
  """
  def row(%{row: %{type: :hero}} = assigns), do: hero_row(assigns.row |> to_attrs())

  def row(%{row: %{type: :content}} = assigns),
    do: content_row(assigns.row |> to_attrs())

  def row(%{row: %{type: :continue_watching}} = assigns),
    do: continue_watching_row(assigns.row |> to_attrs())

  def row(%{row: %{type: :series}} = assigns),
    do: series_row(assigns.row |> to_attrs())

  def row(%{row: %{type: :creator_showcase}} = assigns),
    do: creator_showcase_row(assigns.row |> to_attrs())

  def row(%{row: %{type: :editorial_spotlight}} = assigns),
    do: editorial_spotlight_row(assigns.row |> to_attrs())

  defp to_attrs(row), do: Map.delete(row, :type)

  # ---------------------------------------------------------------------------
  # Hero Image Row
  # ---------------------------------------------------------------------------

  attr :id, :string, default: "hero-row"

  attr :item, :map,
    required: true,
    doc: "Map with :title, :byline, :synopsis, :image_url, :cta_primary, :cta_secondary"

  @doc """
  Full-width cinematic billboard. Always position 0. Own layout, no cards.
  Ken Burns slow zoom on the background image.
  """
  def hero_row(assigns) do
    ~H"""
    <section
      id={@id}
      data-test="row-hero"
      class="relative h-[min(70vh,720px)] min-h-[420px] w-full overflow-hidden bg-bg"
      aria-label={@item.title}
    >
      <div class="absolute inset-0 animate-[ken-burns_20s_ease-in-out_infinite_alternate] motion-reduce:animate-none">
        <img
          src={@item.image_url}
          alt=""
          aria-hidden="true"
          class="h-full w-full object-cover"
        />
      </div>

      <div class="absolute inset-0 bg-gradient-to-t from-bg via-bg/70 to-bg/10" />
      <div class="absolute inset-0 bg-gradient-to-r from-bg via-bg/70 to-transparent" />

      <div class="relative mx-auto flex h-full max-w-7xl items-end px-6 pb-16">
        <div class="max-w-2xl">
          <p class="font-mono text-xs uppercase tracking-wide text-text-muted">
            {@item.byline}
          </p>
          <h1 class="mt-3 font-display text-5xl leading-tight tracking-tighter text-text-primary md:text-6xl">
            {@item.title}
          </h1>
          <p class="mt-4 font-body text-base leading-relaxed text-text-secondary md:text-lg">
            {@item.synopsis}
          </p>

          <div class="mt-6 flex flex-wrap gap-3">
            <a
              href={@item.cta_primary.href}
              data-test="hero-cta-primary"
              class="inline-flex items-center gap-2 rounded-full bg-accent px-5 py-2.5 font-ui text-sm text-accent-text hover:bg-accent-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
            >
              <.icon name="hero-play-solid" class="h-4 w-4" />
              {@item.cta_primary.label}
            </a>
            <a
              href={@item.cta_secondary.href}
              data-test="hero-cta-secondary"
              class="inline-flex items-center gap-2 rounded-full border border-border-strong px-5 py-2.5 font-ui text-sm text-text-primary hover:bg-surface focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
            >
              {@item.cta_secondary.label}
            </a>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Content Row — preferences, tags, popularity, recently added
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :see_all_href, :any, default: nil

  attr :card, :atom,
    required: true,
    values: [:poster_portrait, :landscape_episode, :progress_course]

  attr :items, :list, required: true
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  @doc """
  Standard horizontal carousel. Arrow buttons on desktop hover.
  Stagger reveal on mount. Compatible cards: poster portrait,
  landscape episode, progress course.
  """
  def content_row(assigns) do
    ~H"""
    <.scroll_row
      id={@id}
      title={@title}
      see_all_href={@see_all_href}
      kind="content"
    >
      <.card_item
        :for={item <- @items}
        variant={@card}
        item={item}
        show_details={@show_details}
        title_overlay={@title_overlay}
      />
    </.scroll_row>
    """
  end

  # ---------------------------------------------------------------------------
  # Continue Watching Row — dismiss button, time remaining
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, default: "Continue watching"

  attr :card, :atom,
    required: true,
    values: [:landscape_episode, :progress_course, :poster_portrait]

  attr :items, :list, required: true
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  @doc """
  Like content row with a dismiss button per card and a time-remaining
  label below each card. Renders nothing when `items` is empty — this
  rule is absolute.
  """
  def continue_watching_row(%{items: []} = assigns), do: ~H""

  def continue_watching_row(assigns) do
    ~H"""
    <.scroll_row id={@id} title={@title} see_all_href={nil} kind="continue-watching">
      <div
        :for={item <- @items}
        class={[
          "relative flex-none group/cw",
          continue_watching_card_width(@card)
        ]}
      >
        <button
          type="button"
          phx-click="dismiss_continue"
          phx-value-id={item.id}
          phx-value-kind={if item[:series_id], do: "series", else: "video"}
          aria-label={"Remove #{item.title} from continue watching"}
          data-test={"dismiss-#{item.id}"}
          class="absolute right-2 top-2 z-10 flex h-8 w-8 items-center justify-center rounded-full bg-black/60 text-white opacity-80 transition-opacity duration-150 hover:bg-black/80 hover:opacity-100 focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
        >
          <.icon name="hero-x-mark" class="h-4 w-4" />
        </button>

        <.card_item variant={@card} item={item} />

        <p
          :if={item[:time_remaining]}
          class="mt-2 font-mono text-xs text-text-muted"
        >
          {item.time_remaining} left
        </p>
      </div>
    </.scroll_row>
    """
  end

  # Portrait cards are narrower than landscape ones; keep the row's
  # snap width in sync with the card's intrinsic aspect.
  defp continue_watching_card_width(:poster_portrait), do: "w-40 sm:w-48 md:w-56"
  defp continue_watching_card_width(_), do: "w-64 sm:w-72 md:w-80"

  # ---------------------------------------------------------------------------
  # Series Row — current episode gets accent ring
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :see_all_href, :any, default: nil

  attr :card, :atom,
    required: true,
    values: [:landscape_episode, :progress_course, :minimal_list_item]

  attr :items, :list,
    required: true,
    doc: "Each item may set :current? true to receive the accent ring"

  @doc """
  Sequential episodes. Item with `:current? true` is visually distinguished
  with an accent ring.
  """
  def series_row(assigns) do
    ~H"""
    <.scroll_row id={@id} title={@title} see_all_href={@see_all_href} kind="series">
      <div
        :for={item <- @items}
        class={[
          "flex-none w-64 sm:w-72 md:w-80 rounded-md",
          item[:current?] && "ring-2 ring-accent ring-offset-2 ring-offset-bg"
        ]}
        data-test={item[:current?] && "series-current-#{item.id}"}
      >
        <.card_item variant={@card} item={item} />
      </div>
    </.scroll_row>
    """
  end

  # ---------------------------------------------------------------------------
  # Creator Showcase Row — wider gap, no see-all
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :items, :list, required: true

  @doc """
  Creator identity cards with a wider gap between cards. No "See all"
  link — creator showcase is curated.
  """
  def creator_showcase_row(assigns) do
    ~H"""
    <.scroll_row
      id={@id}
      title={@title}
      see_all_href={nil}
      kind="creator-showcase"
      gap="gap-8"
    >
      <div :for={item <- @items} class="flex-none w-48 sm:w-56">
        <Cards.creator_identity item={item} />
      </div>
    </.scroll_row>
    """
  end

  # ---------------------------------------------------------------------------
  # Editorial Spotlight Row — one wide collection + 2–3 posters
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :collection, :map, required: true
  attr :posters, :list, required: true

  @doc """
  One wide collection editorial card followed by 2–3 poster portrait
  cards in the same scroll container. The editorial card dominates.
  """
  def editorial_spotlight_row(assigns) do
    ~H"""
    <.scroll_row
      id={@id}
      title={@title}
      see_all_href={nil}
      kind="editorial-spotlight"
    >
      <div class="flex-none w-[min(90vw,640px)]">
        <Cards.collection_editorial item={@collection} />
      </div>
      <div :for={item <- @posters} class="flex-none w-40 sm:w-48">
        <Cards.poster_portrait item={item} />
      </div>
    </.scroll_row>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared scroll-row scaffold
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :see_all_href, :any, default: nil
  attr :kind, :string, required: true
  attr :gap, :string, default: "gap-4"
  slot :inner_block, required: true

  defp scroll_row(assigns) do
    ~H"""
    <section
      id={@id}
      phx-hook="Carousel"
      data-test={"row-#{@kind}"}
      class="group/row relative py-6"
    >
      <div class="mx-auto mb-4 flex max-w-7xl items-baseline justify-between gap-4 px-6">
        <h2 class="font-display text-xl leading-tight tracking-tight text-text-primary md:text-2xl">
          {@title}
        </h2>
        <a
          :if={@see_all_href}
          href={@see_all_href}
          data-test={"see-all-#{@kind}"}
          class="font-ui text-sm text-text-secondary hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
        >
          See all →
        </a>
      </div>

      <div class="relative">
        <div
          id={@id <> "-track"}
          data-carousel-track
          phx-hook="StaggerReveal"
          class={[
            "flex snap-x snap-mandatory overflow-x-auto scroll-smooth px-6",
            "[-ms-overflow-style:none] [scrollbar-width:none]",
            "[&::-webkit-scrollbar]:hidden",
            @gap
          ]}
        >
          {render_slot(@inner_block)}
        </div>

        <button
          type="button"
          data-carousel-prev
          aria-label="Scroll left"
          class="absolute left-2 top-1/2 z-10 hidden h-10 w-10 -translate-y-1/2 items-center justify-center rounded-full bg-overlay/90 text-text-primary opacity-0 transition-opacity duration-150 hover:bg-elevated md:group-hover/row:flex md:group-hover/row:opacity-100 focus-visible:flex focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
        >
          <.icon name="hero-chevron-left" class="h-5 w-5" />
        </button>
        <button
          type="button"
          data-carousel-next
          aria-label="Scroll right"
          class="absolute right-2 top-1/2 z-10 hidden h-10 w-10 -translate-y-1/2 items-center justify-center rounded-full bg-overlay/90 text-text-primary opacity-0 transition-opacity duration-150 hover:bg-elevated md:group-hover/row:flex md:group-hover/row:opacity-100 focus-visible:flex focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
        >
          <.icon name="hero-chevron-right" class="h-5 w-5" />
        </button>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Card item wrapper — dispatches to Cards by variant atom
  # ---------------------------------------------------------------------------

  attr :variant, :atom, required: true
  attr :item, :map, required: true
  attr :width_class, :string, default: nil
  attr :show_details, :boolean, default: true
  attr :title_overlay, :boolean, default: false

  defp card_item(%{variant: :poster_portrait} = assigns) do
    assigns = Map.put_new(assigns, :w, "w-40 sm:w-48 md:w-56")

    ~H"""
    <div class={["flex-none snap-start", @w]}>
      <Cards.poster_portrait
        item={@item}
        show_details={@show_details}
        title_overlay={@title_overlay}
      />
    </div>
    """
  end

  defp card_item(%{variant: :landscape_episode} = assigns) do
    assigns = Map.put_new(assigns, :w, "w-64 sm:w-72 md:w-80")

    ~H"""
    <div class={["flex-none snap-start", @w]}>
      <Cards.landscape_episode
        item={@item}
        show_details={@show_details}
        title_overlay={@title_overlay}
      />
    </div>
    """
  end

  defp card_item(%{variant: :progress_course} = assigns) do
    assigns = Map.put_new(assigns, :w, "w-64 sm:w-72 md:w-80")

    ~H"""
    <div class={["flex-none snap-start", @w]}>
      <Cards.progress_course
        item={@item}
        show_details={@show_details}
        title_overlay={@title_overlay}
      />
    </div>
    """
  end

  defp card_item(%{variant: :minimal_list_item} = assigns) do
    ~H"""
    <div class="flex-none w-full snap-start">
      <Cards.minimal_list_item
        item={@item}
        show_details={@show_details}
        title_overlay={@title_overlay}
      />
    </div>
    """
  end
end
