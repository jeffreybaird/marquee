defmodule BobineWeb.Viewer.HomeLive.Components do
  @moduledoc """
  Extracted components for HomeLive page modes and reusable UI blocks.

  - `platform_marketing/1` — Bobine marketing page (no org resolved)
  - `org_landing/1` — org landing page (org resolved, no viewer auth)
  - `feature_card/1` — feature highlight card for marketing page
  - `hero_carousel/1` — hero slide carousel for org home
  - `content_row/1` — horizontal scrollable row of video cards
  - `welcome_state/1` — warm onboarding banner for viewers with no watch history
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
                href={slide.primary_cta_path}
                class="hero-cta-primary"
                data-test={"hero-primary-cta-#{index}"}
              >
                {slide.primary_cta_label}
              </.link>
              <.link
                :if={slide.secondary_cta_path}
                href={slide.secondary_cta_path}
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
    assigns = assign(assigns, :card_variant, resolve_card_variant(assigns.row))

    ~H"""
    <section
      class="content-row"
      id={"row-#{@row.id}"}
      phx-hook="RowScroller"
      data-test={"content-row-#{@row.id}"}
      data-card-variant={@card_variant}
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
        <div class="content-row-items" data-card-variant={@card_variant}>
          <ViewerComponents.content_item_card
            :for={item <- @items}
            item={item}
            size="row"
            current_viewer={@current_viewer}
            card_id={item_card_id(@row, item)}
            favorited_ids={@favorited_ids}
            watchlisted_ids={@watchlisted_ids}
            queued_ids={@queued_ids}
            preview_on_hover={@card_variant != "poster_portrait"}
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

  # The row's stored `card_variant` wins; when nil (legacy rows created
  # before card_variant landed) we fall back to the default variant for
  # this row's source type. Always emits a string attribute safe for CSS
  # attribute-selector targeting.
  @default_variant_by_row_type %{
    hero: "collection_editorial",
    popularity: "poster_portrait",
    tags: "poster_portrait",
    preferences: "poster_portrait",
    series: "landscape_episode",
    continue_watching: "landscape_episode",
    creator_showcase: "creator_identity",
    editorial_spotlight: "collection_editorial"
  }

  defp resolve_card_variant(%{card_variant: variant}) when is_binary(variant) and variant != "",
    do: variant

  defp resolve_card_variant(%{source_type: source_type}) when not is_nil(source_type) do
    row_type = Bobine.Catalog.Row.compat_row_type(source_type)
    Map.get(@default_variant_by_row_type, row_type, "landscape_episode")
  end

  defp resolve_card_variant(_), do: "landscape_episode"

  ## ─────────────────────────────────────────────────────────────────────
  ## Landing page section components
  ## ─────────────────────────────────────────────────────────────────────

  attr :section, :map, required: true
  attr :organization, :map, required: true

  def landing_section(assigns) do
    ~H"""
    <section
      class={"sv-landing-section sv-landing-#{@section.section_type}"}
      data-test={"landing-section-#{@section.id}"}
    >
      <%= case @section.section_type do %>
        <% :hero_video -> %>
          <.landing_hero_video config={@section.config} />
        <% :hero_image -> %>
          <.landing_hero_image config={@section.config} />
        <% :hero_slider -> %>
          <.landing_hero_slider config={@section.config} />
        <% :marketing_copy -> %>
          <.landing_marketing_copy config={@section.config} />
        <% :content_row -> %>
          <.landing_content_row config={@section.config} />
        <% :plan_display -> %>
          <.landing_plan_display config={@section.config} />
        <% :header_text -> %>
          <.landing_header_text config={@section.config} />
        <% :faq -> %>
          <.landing_faq config={@section.config} />
      <% end %>
    </section>
    """
  end

  attr :config, :map, required: true

  def landing_hero_video(assigns) do
    assigns =
      assigns
      |> assign(:playback_id, hero_playback_id(assigns.config))
      |> assign(:video_url, hero_video_url(assigns.config))

    ~H"""
    <div class="sv-hero-video" data-test="hero-video-section">
      <mux-player
        :if={@playback_id}
        stream-type="on-demand"
        playback-id={@playback_id}
        autoplay="muted"
        muted
        loop
        preload="auto"
        disable-cookies
        disable-tracking
        poster={@config["fallback_image_url"]}
        class="sv-hero-video-bg"
        aria-hidden="true"
      >
      </mux-player>

      <video
        :if={!@playback_id && @video_url}
        autoplay
        muted
        loop
        playsinline
        poster={@config["fallback_image_url"]}
        class="sv-hero-video-bg"
        aria-hidden="true"
      >
        <source src={@video_url} type="video/mp4" />
      </video>

      <div
        class="sv-hero-overlay"
        style={"opacity: #{@config["overlay_opacity"] || 0.5}"}
        aria-hidden="true"
      >
      </div>

      <div class="sv-hero-content">
        <h1 class="sv-hero-headline">{@config["headline"]}</h1>
        <p :if={@config["subheadline"]} class="sv-hero-subheadline">
          {@config["subheadline"]}
        </p>
        <.link
          :if={@config["cta_text"]}
          navigate={@config["cta_link"] || "/subscribe"}
          class="sv-hero-cta"
          data-test="hero-cta"
        >
          {@config["cta_text"]}
        </.link>
      </div>
    </div>
    """
  end

  attr :config, :map, required: true

  def landing_hero_image(assigns) do
    ~H"""
    <div class="sv-hero-image" data-test="hero-image-section">
      <img src={@config["image_url"]} alt="" class="sv-hero-image-bg" />
      <div
        class="sv-hero-overlay"
        style={"opacity: #{@config["overlay_opacity"] || 0.5}"}
        aria-hidden="true"
      >
      </div>
      <div class="sv-hero-content">
        <h1 class="sv-hero-headline">{@config["headline"]}</h1>
        <p :if={@config["subheadline"]} class="sv-hero-subheadline">
          {@config["subheadline"]}
        </p>
        <.link
          :if={@config["cta_text"]}
          navigate={@config["cta_link"] || "/subscribe"}
          class="sv-hero-cta"
          data-test="hero-cta"
        >
          {@config["cta_text"]}
        </.link>
      </div>
    </div>
    """
  end

  attr :config, :map, required: true

  def landing_hero_slider(assigns) do
    ~H"""
    <div data-test="hero-slider-section">
      <%= if (@config["slides"] || []) != [] do %>
        <.hero_carousel slides={@config["slides"]} auto_advance_ms={8000} />
      <% end %>
    </div>
    """
  end

  attr :config, :map, required: true

  def landing_marketing_copy(assigns) do
    alignment = assigns.config["text_alignment"] || "center"
    assigns = assign(assigns, :alignment, alignment)

    ~H"""
    <div
      class="sv-marketing-copy"
      style={build_marketing_bg_style(@config)}
      data-test="marketing-copy-section"
    >
      <div class={"sv-marketing-inner sv-text-#{@alignment}"}>
        <h2 :if={@config["headline"]} class="sv-marketing-headline">
          {@config["headline"]}
        </h2>
        <p :if={@config["body"]} class="sv-marketing-body">
          {@config["body"]}
        </p>
        <.link
          :if={@config["cta_text"]}
          navigate={@config["cta_link"] || "/subscribe"}
          class="sv-marketing-cta"
          data-test="marketing-cta"
        >
          {@config["cta_text"]}
        </.link>
      </div>
    </div>
    """
  end

  attr :config, :map, required: true

  def landing_content_row(assigns) do
    ~H"""
    <div class="sv-landing-row" data-test="content-row-section">
      <h2 :if={@config["title"]} class="sv-row-title">{@config["title"]}</h2>
      <div class="sv-row-scroll">
        <ViewerComponents.content_item_card
          :for={item <- @config["items"] || []}
          item={item}
          size="row"
        />
      </div>
    </div>
    """
  end

  attr :config, :map, required: true

  def landing_plan_display(assigns) do
    ~H"""
    <div class="sv-plan-display" data-test="plan-display-section">
      <h2 :if={@config["headline"]} class="sv-plan-headline">
        {@config["headline"]}
      </h2>
      <p :if={@config["subheadline"]} class="sv-plan-subheadline">
        {@config["subheadline"]}
      </p>

      <div class="sv-plan-grid">
        <div
          :for={plan <- @config["plans"] || []}
          class="sv-plan-card"
          data-test={"plan-card-#{plan.id}"}
        >
          <h3 class="sv-plan-name">{plan.name}</h3>
          <div class="sv-plan-price">
            <span class="sv-plan-amount">${format_cents(plan.amount)}</span>
            <span class="sv-plan-interval">/ {plan.interval}</span>
          </div>
          <p :if={plan.trial_period_days} class="sv-plan-trial">
            {plan.trial_period_days}-day free trial
          </p>
          <ul :if={plan.features != []} class="sv-plan-features">
            <li :for={feature <- plan.features}>{feature}</li>
          </ul>
          <.link
            navigate={~p"/subscribe"}
            class="sv-plan-cta"
            data-test={"plan-cta-#{plan.id}"}
          >
            {if plan.trial_period_days, do: "Start free trial", else: "Subscribe"}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :config, :map, required: true

  def landing_header_text(assigns) do
    size_class =
      case assigns.config["size"] do
        "small" -> "sv-header-sm"
        "large" -> "sv-header-lg"
        _ -> "sv-header-md"
      end

    alignment = assigns.config["text_alignment"] || "center"

    assigns = assign(assigns, size_class: size_class, alignment: alignment)

    ~H"""
    <div
      class={"sv-header-text #{@size_class} sv-text-#{@alignment}"}
      data-test="header-text-section"
    >
      <h2>{@config["headline"]}</h2>
      <p :if={@config["subheadline"]}>{@config["subheadline"]}</p>
    </div>
    """
  end

  attr :config, :map, required: true

  def landing_faq(assigns) do
    ~H"""
    <div class="sv-faq" data-test="faq-section">
      <h2 :if={@config["headline"]} class="sv-faq-headline">
        {@config["headline"]}
      </h2>

      <div class="sv-faq-list">
        <details
          :for={{item, index} <- Enum.with_index(@config["items"] || [])}
          class="sv-faq-item"
          data-test={"faq-item-#{index}"}
        >
          <summary class="sv-faq-question">{item["question"]}</summary>
          <p class="sv-faq-answer">{item["answer"]}</p>
        </details>
      </div>
    </div>
    """
  end

  defp hero_video_url(%{"video_url" => url}) when is_binary(url) and url != "", do: url
  defp hero_video_url(_), do: nil

  defp hero_playback_id(%{"video_playback_id" => id}) when is_binary(id) and id != "", do: id
  defp hero_playback_id(_), do: nil

  defp build_marketing_bg_style(config) do
    cond do
      config["background_image_url"] && config["background_image_url"] != "" ->
        "background-image: url('#{config["background_image_url"]}'); background-size: cover; background-position: center;"

      config["background_color"] && config["background_color"] != "" ->
        "background-color: #{config["background_color"]};"

      true ->
        ""
    end
  end

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)

    if remainder == 0 do
      Integer.to_string(dollars)
    else
      "#{dollars}.#{String.pad_leading(Integer.to_string(remainder), 2, "0")}"
    end
  end

  defp format_cents(_), do: "0"

  attr :organization, :map, required: true
  attr :browse_href, :string, default: "/browse"

  @doc """
  Warm onboarding banner shown in place of an empty continue-watching row
  when a viewer has no watch history. Encourages exploration without
  showing a bare or empty section.
  """
  def welcome_state(assigns) do
    ~H"""
    <section
      class="sv-welcome relative overflow-hidden rounded-lg border border-border-subtle bg-surface px-6 py-10 sm:px-10 sm:py-14"
      data-test="viewer-welcome-state"
      aria-labelledby="welcome-heading"
    >
      <div class="max-w-2xl">
        <p class="font-mono text-xs uppercase tracking-[0.2em] text-text-muted">
          Welcome to {@organization.name}
        </p>
        <h2
          id="welcome-heading"
          class="mt-3 font-display text-3xl leading-tight tracking-tight text-text-primary sm:text-4xl"
        >
          Find your first favorite.
        </h2>
        <p class="mt-3 font-body text-base leading-relaxed text-text-secondary">
          Browse the full catalog, save what catches your eye, and we'll pick up where you leave off every time you return.
        </p>
        <div class="mt-6 flex flex-wrap gap-3">
          <.link
            href={@browse_href}
            class="inline-flex items-center gap-2 rounded-full bg-accent px-5 py-2.5 font-ui text-sm text-accent-text hover:bg-accent-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
            data-test="welcome-browse-btn"
          >
            Browse the catalog
          </.link>
        </div>
      </div>
    </section>
    """
  end
end
