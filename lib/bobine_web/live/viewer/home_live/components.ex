defmodule BobineWeb.Viewer.HomeLive.Components do
  @moduledoc """
  Extracted components for HomeLive page modes and reusable UI blocks.

  - `platform_marketing/1` — Bobine marketing page (no org resolved)
  - `org_landing/1` — org landing page (org resolved, no viewer auth)
  - `feature_card/1` — feature highlight card for marketing page
  - `hero_carousel/1` — hero slide carousel for org home
  - `content_row/1` — horizontal scrollable row of video cards
  """

  use BobineWeb, :html

  alias BobineWeb.Components.ViewerComponents

  attr :organization, :map, required: true

  def org_landing(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100" data-test="org-landing">
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
        <div class="flex-1">
          <a href="/" class="text-xl font-bold tracking-tight text-base-content">
            {@organization.name}
          </a>
        </div>
        <nav class="flex-none flex items-center gap-3">
          <.link
            navigate={~p"/login"}
            class="btn btn-ghost btn-sm"
            data-test="org-landing-login-link"
          >
            Sign in
          </.link>
          <.link
            navigate={~p"/register"}
            class="btn btn-primary btn-sm"
            data-test="org-landing-register-link"
          >
            Join
          </.link>
        </nav>
      </header>

      <main>
        <section class="relative overflow-hidden bg-gradient-to-br from-primary/10 via-base-100 to-accent/10 py-24 sm:py-32">
          <div class="mx-auto max-w-4xl px-6 text-center">
            <h1
              class="text-4xl font-extrabold tracking-tight text-base-content sm:text-6xl"
              data-test="org-landing-headline"
            >
              Welcome to {@organization.name}
            </h1>
            <p class="mt-6 text-lg leading-8 text-base-content/70 sm:text-xl">
              Discover exclusive video content. Sign in or create an account to start watching.
            </p>
            <div class="mt-10 flex items-center justify-center gap-4">
              <.link
                navigate={~p"/register"}
                class="btn btn-primary btn-lg"
                data-test="org-landing-hero-cta"
              >
                Create an account
              </.link>
              <.link
                navigate={~p"/login"}
                class="btn btn-ghost btn-lg"
                data-test="org-landing-hero-login"
              >
                Sign in
              </.link>
            </div>
          </div>
        </section>

        <section class="py-16 sm:py-20" data-test="org-landing-features">
          <div class="mx-auto max-w-4xl px-6">
            <div class="grid gap-8 sm:grid-cols-3">
              <div class="text-center">
                <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-primary/10">
                  <.icon name="hero-play-circle" class="size-6 text-primary" />
                </div>
                <h3 class="mt-4 font-semibold text-base-content">Stream anytime</h3>
                <p class="mt-2 text-sm text-base-content/70">
                  Watch on any device, anywhere.
                </p>
              </div>
              <div class="text-center">
                <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-primary/10">
                  <.icon name="hero-sparkles" class="size-6 text-primary" />
                </div>
                <h3 class="mt-4 font-semibold text-base-content">Exclusive content</h3>
                <p class="mt-2 text-sm text-base-content/70">
                  Access videos you won't find anywhere else.
                </p>
              </div>
              <div class="text-center">
                <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-primary/10">
                  <.icon name="hero-heart" class="size-6 text-primary" />
                </div>
                <h3 class="mt-4 font-semibold text-base-content">Support creators</h3>
                <p class="mt-2 text-sm text-base-content/70">
                  Your subscription directly supports the people who make the content you love.
                </p>
              </div>
            </div>
          </div>
        </section>
      </main>

      <footer class="border-t border-base-300 py-8 text-center text-sm text-base-content/50">
        &copy; {Date.utc_today().year} {@organization.name}. Powered by Bobine.
      </footer>
    </div>
    """
  end

  def platform_marketing(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100" data-test="platform-marketing">
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
        <div class="flex-1">
          <a href="/" class="text-xl font-bold tracking-tight text-base-content">Bobine</a>
        </div>
        <nav class="flex-none flex items-center gap-3">
          <.link
            navigate={~p"/users/log-in"}
            class="btn btn-ghost btn-sm"
            data-test="marketing-login-link"
          >
            Log in
          </.link>
          <.link
            navigate={~p"/users/register"}
            class="btn btn-primary btn-sm"
            data-test="marketing-register-link"
          >
            Get started
          </.link>
        </nav>
      </header>

      <main>
        <%!-- Hero --%>
        <section class="relative overflow-hidden bg-gradient-to-br from-primary/10 via-base-100 to-accent/10 py-24 sm:py-32">
          <div class="mx-auto max-w-4xl px-6 text-center">
            <h1
              class="text-4xl font-extrabold tracking-tight text-base-content sm:text-6xl"
              data-test="marketing-headline"
            >
              Launch your own streaming platform
            </h1>
            <p class="mt-6 text-lg leading-8 text-base-content/70 sm:text-xl">
              Bobine gives creators and businesses everything they need to publish, monetize,
              and grow a branded video streaming service — no engineering team required.
            </p>
            <div class="mt-10 flex items-center justify-center gap-4">
              <.link
                navigate={~p"/users/register"}
                class="btn btn-primary btn-lg"
                data-test="marketing-hero-cta"
              >
                Start for free
              </.link>
              <.link
                navigate={~p"/users/log-in"}
                class="btn btn-ghost btn-lg"
                data-test="marketing-hero-login"
              >
                Log in
              </.link>
            </div>
          </div>
        </section>

        <%!-- Features --%>
        <section class="py-20 sm:py-24" data-test="marketing-features">
          <div class="mx-auto max-w-6xl px-6">
            <h2 class="text-center text-2xl font-bold text-base-content sm:text-3xl">
              Everything you need to run a streaming service
            </h2>
            <div class="mt-12 grid gap-8 sm:grid-cols-2 lg:grid-cols-3">
              <.feature_card
                icon="hero-play-circle"
                title="Professional Video"
                description="Upload once and deliver adaptive bitrate streams worldwide, powered by Mux."
              />
              <.feature_card
                icon="hero-credit-card"
                title="Built-in Monetization"
                description="Offer subscriptions and manage payments with Stripe — no custom integration needed."
              />
              <.feature_card
                icon="hero-paint-brush"
                title="Your Brand, Your Rules"
                description="Custom domains, logos, colors, and templates so viewers see your brand, not ours."
              />
              <.feature_card
                icon="hero-chart-bar"
                title="Audience Analytics"
                description="Understand what your viewers watch, how long they stay, and what drives growth."
              />
              <.feature_card
                icon="hero-users"
                title="Team Management"
                description="Invite editors, support staff, and admins with granular role-based permissions."
              />
              <.feature_card
                icon="hero-bolt"
                title="Launch Fast"
                description="Go from zero to a live streaming site in minutes, not months."
              />
            </div>
          </div>
        </section>

        <%!-- CTA --%>
        <section class="border-t border-base-300 bg-base-200 py-16 sm:py-20">
          <div class="mx-auto max-w-3xl px-6 text-center">
            <h2 class="text-2xl font-bold text-base-content sm:text-3xl">
              Ready to build your streaming platform?
            </h2>
            <p class="mt-4 text-base-content/70">
              Join creators and businesses already using Bobine to reach their audience.
            </p>
            <.link
              navigate={~p"/users/register"}
              class="btn btn-primary btn-lg mt-8"
              data-test="marketing-bottom-cta"
            >
              Get started for free
            </.link>
          </div>
        </section>
      </main>

      <footer class="border-t border-base-300 py-8 text-center text-sm text-base-content/50">
        &copy; {Date.utc_today().year} Bobine. All rights reserved.
      </footer>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  def feature_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-300 bg-base-200 p-6">
      <div class="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
        <.icon name={@icon} class="size-5 text-primary" />
      </div>
      <h3 class="mt-4 text-lg font-semibold text-base-content">{@title}</h3>
      <p class="mt-2 text-sm leading-6 text-base-content/70">{@description}</p>
    </div>
    """
  end

  attr :slides, :list, required: true
  attr :auto_advance_ms, :integer, required: true

  def hero_carousel(assigns) do
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
  attr :items, :list, required: true
  attr :view_all_path, :string, default: nil
  attr :current_viewer, :map, default: nil
  attr :favorited_ids, :any, default: MapSet.new()
  attr :watchlisted_ids, :any, default: MapSet.new()
  attr :queued_ids, :any, default: MapSet.new()

  def content_row(assigns) do
    ~H"""
    <section
      class="content-row"
      id={"row-#{@row.id}"}
      phx-hook="RowScroller"
      data-test={"content-row-#{@row.id}"}
    >
      <div class="content-row-header">
        <h2 class="content-row-title">{@row.title}</h2>
        <.link
          :if={@view_all_path}
          navigate={@view_all_path}
          class="content-row-view-all"
          data-test={"view-all-#{@row.id}"}
          aria-label={"View all #{@row.title}"}
        >
          <span class="view-all-text">View All</span>
          <.icon name="hero-chevron-right" class="view-all-chevron size-4" aria-hidden="true" />
        </.link>
      </div>
      <div class="content-row-scroll">
        <button
          class="row-arrow row-arrow-prev row-arrow-hidden"
          aria-label="Scroll left"
          data-test={"row-arrow-prev-#{@row.id}"}
        >
          <.icon name="hero-chevron-left" class="size-5" aria-hidden="true" />
        </button>
        <div class="content-row-items">
          <ViewerComponents.content_item_card
            :for={item <- @items}
            item={item}
            size="row"
            current_viewer={@current_viewer}
            card_id={item_card_id(@row, item)}
            favorited_ids={@favorited_ids}
            watchlisted_ids={@watchlisted_ids}
            queued_ids={@queued_ids}
          />
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

  defp item_card_id(row, %{type: :next_season, season: %{id: season_id}}),
    do: "home-row-#{row.id}-card-season-#{season_id}"

  defp item_card_id(row, %{type: type, video: %{id: video_id}})
       when type in [:in_progress, :between_episodes],
       do: "home-row-#{row.id}-card-#{video_id}"

  defp item_card_id(row, item) do
    "home-row-#{row.id}-card-#{item.id}"
  end
end
