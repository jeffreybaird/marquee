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
        hero_items = Catalog.build_hero_items(org, limit: 5)
        rows = load_catalog_rows(org)

        {:ok,
         socket
         |> assign(:page_title, org.name)
         |> assign(:hero_items, hero_items)
         |> assign(:rows, rows)}

      # No org, no super admin -> show generic landing
      true ->
        {:ok,
         socket
         |> assign(:page_title, "Welcome")
         |> assign(:hero_items, [])
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
      <.hero_carousel :if={@hero_items != []} items={@hero_items} />

      <div :if={@hero_items == [] && @rows == []} class="py-12 text-center text-base-content/60">
        <p class="text-lg">No videos available yet.</p>
      </div>

      <%!-- Catalog rows --%>
      <section :if={@rows != []} class="catalog-rows" data-test="catalog-rows">
        <.content_row :for={%{row: row, videos: videos} <- @rows} row={row} videos={videos} />
      </section>
    </ViewerLayout.viewer_layout>
    """
  end

  attr :items, :list, required: true

  defp hero_carousel(assigns) do
    ~H"""
    <section
      id="hero-carousel"
      phx-hook="HeroCarousel"
      data-auto-advance="8000"
      data-test="hero-carousel"
      class="hero-carousel-wrapper"
    >
      <%!-- Background slides --%>
      <div class="hero-slides">
        <div
          :for={{item, index} <- Enum.with_index(@items)}
          class={["hero-slide", index == 0 && "active"]}
          data-index={index}
          data-test={"hero-slide-#{index}"}
        >
          <%!-- Background image with gradient overlay --%>
          <div class="hero-bg">
            <img
              :if={item.background_image_url}
              src={item.background_image_url}
              alt={item.title}
              loading={if index == 0, do: "eager", else: "lazy"}
            />
            <div class="hero-gradient" />
          </div>

          <%!-- Content overlay (left-aligned) --%>
          <div class="hero-content" data-test={"hero-content-#{index}"}>
            <span :if={item.brand_tag} class="hero-brand-tag">{item.brand_tag}</span>
            <h1 class="hero-title">{item.title}</h1>
            <p :if={item.status_text} class="hero-status">{item.status_text}</p>
            <p :if={item.metadata_text} class="hero-metadata">{item.metadata_text}</p>

            <%!-- CTA group --%>
            <div class="hero-cta-group">
              <.link
                navigate={item.primary_cta_path}
                class="hero-cta-primary"
                data-test={"hero-primary-cta-#{index}"}
              >
                {item.primary_cta_label}
              </.link>
              <.link
                :if={item.secondary_cta_path}
                navigate={item.secondary_cta_path}
                class="hero-cta-secondary"
                data-test={"hero-secondary-cta-#{index}"}
              >
                {item.secondary_cta_label}
              </.link>
            </div>
          </div>
        </div>
      </div>

      <%!-- Pagination dots --%>
      <div class="hero-pagination" data-test="hero-pagination">
        <button
          :for={{_item, index} <- Enum.with_index(@items)}
          class={["hero-dot", index == 0 && "active"]}
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
    <section class="content-row" data-test={"content-row-#{@row.id}"}>
      <h2 class="content-row-title">{@row.title}</h2>
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
    </section>
    """
  end

  defp load_catalog_rows(org) do
    %{results: rows} = Catalog.list_visible_rows(org, per_page: 100)

    rows
    |> Enum.map(fn row ->
      %{results: videos} = Catalog.resolve_row_content_cached(org, row, per_page: row.max_items)
      %{row: row, videos: videos}
    end)
    |> Enum.reject(fn %{videos: videos} -> Enum.empty?(videos) end)
  end
end
