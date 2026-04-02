# TODO: Convert to static page with LiveView islands for hero carousel
# and any interactive elements. The catalog rows are read-only and should
# be server-rendered HTML for performance at scale.
defmodule BobineWeb.Viewer.HomeLive do
  use BobineWeb, :live_view

  alias Bobine.Catalog
  alias BobineWeb.Components.ViewerLayout

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns[:organization]

    cond do
      # Super admin with no org resolved -> send to super admin dashboard
      scope && scope.user && scope.user.is_super_admin && is_nil(org) ->
        {:ok, push_navigate(socket, to: ~p"/super")}

      # Authenticated user with org resolved -> show org home
      org ->
        %{slides: hero_slides, auto_advance_ms: auto_advance_ms} =
          Catalog.resolve_hero_slides_cached(org)

        rows = load_catalog_rows(org)

        {:ok,
         socket
         |> assign(:page_title, org.name)
         |> assign(:hero_slides, hero_slides)
         |> assign(:hero_auto_advance_ms, auto_advance_ms)
         |> assign(:rows, rows)}

      # No org, no super admin -> show generic landing
      true ->
        {:ok,
         socket
         |> assign(:page_title, "Welcome")
         |> assign(:hero_slides, [])
         |> assign(:hero_auto_advance_ms, 0)
         |> assign(:rows, [])}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ViewerLayout.viewer_layout
      organization={@organization}
      current_viewer={@current_viewer}
      impersonating_viewer={@impersonating_viewer}
      current_path="/"
      flash={@flash}
    >
      <%!-- Hero carousel --%>
      <.hero_carousel
        :if={@hero_slides != []}
        slides={@hero_slides}
        auto_advance_ms={@hero_auto_advance_ms}
      />

      <div
        :if={@hero_slides == [] && @rows == []}
        class="py-12 text-center text-base-content/60"
      >
        <p class="text-lg">No videos available yet.</p>
      </div>

      <%!-- Catalog rows --%>
      <section :if={@rows != []} class="catalog-rows" data-test="catalog-rows">
        <.content_row :for={%{row: row, videos: videos} <- @rows} row={row} videos={videos} />
      </section>
    </ViewerLayout.viewer_layout>
    """
  end

  attr :slides, :list, required: true
  attr :auto_advance_ms, :integer, required: true

  defp hero_carousel(assigns) do
    ~H"""
    <section
      id="hero-carousel"
      phx-hook="HeroCarousel"
      data-auto-advance={@auto_advance_ms}
      data-test="hero-carousel"
      class="hero-carousel-wrapper"
      aria-roledescription="carousel"
      aria-label="Featured content"
    >
      <%!-- Background slides --%>
      <div class="hero-slides" aria-live="off">
        <div
          :for={{slide, index} <- Enum.with_index(@slides)}
          class={["hero-slide", index == 0 && "active"]}
          role="group"
          aria-roledescription="slide"
          aria-label={"Slide #{index + 1} of #{length(@slides)}: #{slide.headline}"}
          data-index={index}
          data-test={"hero-slide-#{index}"}
        >
          <%!-- Background image with gradient overlay --%>
          <div class="hero-bg">
            <img
              :if={slide.background_image_url}
              src={slide.background_image_url}
              alt={slide.headline}
              loading={if index == 0, do: "eager", else: "lazy"}
            />
            <div class="hero-gradient" aria-hidden="true" />
          </div>

          <%!-- Content overlay (left-aligned) --%>
          <div class="hero-content" data-test={"hero-content-#{index}"}>
            <span :if={slide.brand_tag} class="hero-brand-tag">{slide.brand_tag}</span>
            <h1 class="hero-title">{slide.headline}</h1>
            <p :if={slide.subheadline} class="hero-status">{slide.subheadline}</p>
            <p :if={slide.description} class="hero-metadata">{slide.description}</p>

            <%!-- CTA group --%>
            <div class="hero-cta-group">
              <.link
                navigate={slide.primary_cta_path}
                class="hero-cta-primary"
                data-test={"hero-primary-cta-#{index}"}
              >
                {slide.primary_cta_label}
              </.link>
              <.link
                :if={slide.secondary_cta_path}
                navigate={slide.secondary_cta_path}
                class="hero-cta-secondary"
                data-test={"hero-secondary-cta-#{index}"}
              >
                {slide.secondary_cta_label}
              </.link>
            </div>
          </div>
        </div>
      </div>

      <%!-- Navigation arrows --%>
      <button
        class="hero-arrow hero-arrow-prev"
        aria-label="Previous slide"
        data-test="hero-arrow-prev"
      >
        <.icon name="hero-chevron-left" class="size-6" aria-hidden="true" />
      </button>
      <button
        class="hero-arrow hero-arrow-next"
        aria-label="Next slide"
        data-test="hero-arrow-next"
      >
        <.icon name="hero-chevron-right" class="size-6" aria-hidden="true" />
      </button>

      <%!-- Pagination dots --%>
      <div
        class="hero-pagination"
        role="tablist"
        aria-label="Slide controls"
        data-test="hero-pagination"
      >
        <button
          :for={{_slide, index} <- Enum.with_index(@slides)}
          class={["hero-dot", index == 0 && "active"]}
          role="tab"
          aria-selected={if index == 0, do: "true", else: "false"}
          data-index={index}
          aria-label={"Go to slide #{index + 1}"}
          data-test={"hero-dot-#{index}"}
        />
      </div>
    </section>
    """
  end

  attr :row, :map, required: true
  attr :videos, :list, required: true

  defp content_row(assigns) do
    ~H"""
    <section
      class="content-row"
      id={"row-#{@row.id}"}
      phx-hook="RowScroller"
      data-test={"content-row-#{@row.id}"}
    >
      <h2 class="content-row-title">{@row.title}</h2>
      <div class="content-row-scroll">
        <button
          class="row-arrow row-arrow-prev row-arrow-hidden"
          aria-label="Scroll left"
          data-test={"row-arrow-prev-#{@row.id}"}
        >
          <.icon name="hero-chevron-left" class="size-5" aria-hidden="true" />
        </button>
        <div class="content-row-items">
          <.link
            :for={video <- @videos}
            navigate={~p"/watch/#{video.id}"}
            class="content-card"
            data-test={"content-card-#{video.id}"}
          >
            <img
              :if={video.mux_playback_id}
              src={"https://image.mux.com/#{video.mux_playback_id}/thumbnail.webp?width=400&height=225&fit_mode=smartcrop"}
              alt={video.title}
              loading="lazy"
            />
            <span class="content-card-title">{video.title}</span>
          </.link>
        </div>
        <button
          class="row-arrow row-arrow-next"
          aria-label="Scroll right"
          data-test={"row-arrow-next-#{@row.id}"}
        >
          <.icon name="hero-chevron-right" class="size-5" aria-hidden="true" />
        </button>
      </div>
    </section>
    """
  end

  defp load_catalog_rows(org) do
    %{results: rows} = Catalog.list_visible_rows(org, per_page: 100)

    rows
    |> Enum.reject(&(&1.source_type == :hero))
    |> Enum.map(fn row ->
      %{results: videos} = Catalog.resolve_row_content_cached(org, row, per_page: row.max_items)
      %{row: row, videos: videos}
    end)
    |> Enum.reject(fn %{videos: videos} -> Enum.empty?(videos) end)
  end
end
