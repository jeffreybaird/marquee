defmodule MarqueeWeb.Dev.CardShowcaseLive do
  @moduledoc """
  Development-only showcase of the card variant catalog.

  Renders every card variant in the brand system alongside its skeleton
  state, using realistic seeded mock data. Serves as a visual benchmark
  for Stage 1 of the viewer UI rebuild. Not mounted in production —
  route is gated behind `:dev_routes` in `router.ex`.
  """

  use MarqueeWeb, :live_view

  alias MarqueeWeb.Components.Cards
  alias MarqueeWeb.Components.Rows

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Card Catalog")
     |> assign(:posters, posters())
     |> assign(:episodes, episodes())
     |> assign(:creators, creators())
     |> assign(:collections, collections())
     |> assign(:courses, courses())
     |> assign(:list_items, list_items())
     |> assign(:continue_items, continue_items())
     |> assign(:continue_empty, [])
     |> assign(:series_items, series_items())
     |> assign(:hero, hero_item()), layout: false}
  end

  @impl true
  def handle_event("dismiss_continue", %{"id" => _id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-bg text-text-primary font-ui">
      <header class="border-b border-border-subtle">
        <div class="mx-auto max-w-7xl px-6 py-10">
          <p class="font-mono text-xs uppercase tracking-wide text-text-muted">
            Stage 1 · Development preview
          </p>
          <h1 class="mt-2 font-display text-4xl leading-tight tracking-tighter text-text-primary">
            Card variant catalog
          </h1>
          <p class="mt-3 max-w-2xl font-body text-base leading-relaxed text-text-secondary">
            Six atomic card variants plus their skeleton states. Semantic tokens
            resolve once the theme layer from Stage 2 lands.
          </p>

          <nav class="mt-6 flex flex-wrap gap-x-6 gap-y-2 font-ui text-sm text-text-secondary">
            <a href="#poster-portrait" class="hover:text-accent">Poster portrait</a>
            <a href="#landscape-episode" class="hover:text-accent">Landscape episode</a>
            <a href="#creator-identity" class="hover:text-accent">Creator identity</a>
            <a href="#collection-editorial" class="hover:text-accent">Collection editorial</a>
            <a href="#progress-course" class="hover:text-accent">Progress course</a>
            <a href="#minimal-list-item" class="hover:text-accent">Minimal list item</a>
          </nav>
        </div>
      </header>

      <div class="mx-auto max-w-7xl space-y-20 px-6 py-16">
        <.section
          id="poster-portrait"
          title="Poster Portrait"
          ratio="2:3"
          rows="hero · popularity · tags · preferences · editorial"
        >
          <:live>
            <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-5">
              <div :for={item <- @posters} class="w-full">
                <Cards.poster_portrait item={item} />
              </div>
            </div>
          </:live>
          <:skeleton>
            <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-5">
              <Cards.poster_portrait_skeleton :for={_ <- 1..5} />
            </div>
          </:skeleton>
        </.section>

        <.section
          id="landscape-episode"
          title="Landscape Episode"
          ratio="16:9"
          rows="series · continue watching · recently added"
        >
          <:live>
            <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
              <div :for={item <- @episodes} class="w-full">
                <Cards.landscape_episode item={item} />
              </div>
            </div>
          </:live>
          <:skeleton>
            <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
              <Cards.landscape_episode_skeleton :for={_ <- 1..3} />
            </div>
          </:skeleton>
        </.section>

        <.section id="creator-identity" title="Creator Identity" ratio="1:1" rows="creator showcase">
          <:live>
            <div class="grid grid-cols-2 gap-5 sm:grid-cols-3 md:grid-cols-4">
              <div :for={item <- @creators} class="w-full">
                <Cards.creator_identity item={item} />
              </div>
            </div>
          </:live>
          <:skeleton>
            <div class="grid grid-cols-2 gap-5 sm:grid-cols-3 md:grid-cols-4">
              <Cards.creator_identity_skeleton :for={_ <- 1..4} />
            </div>
          </:skeleton>
        </.section>

        <.section
          id="collection-editorial"
          title="Collection Editorial"
          ratio="3:2"
          rows="hero · editorial spotlight"
        >
          <:live>
            <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
              <div :for={item <- @collections} class="w-full">
                <Cards.collection_editorial item={item} />
              </div>
            </div>
          </:live>
          <:skeleton>
            <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
              <Cards.collection_editorial_skeleton :for={_ <- 1..2} />
            </div>
          </:skeleton>
        </.section>

        <.section
          id="progress-course"
          title="Progress Course"
          ratio="16:9 + metadata"
          rows="continue watching · series · preferences"
        >
          <:live>
            <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
              <div :for={item <- @courses} class="w-full">
                <Cards.progress_course item={item} />
              </div>
            </div>
          </:live>
          <:skeleton>
            <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
              <Cards.progress_course_skeleton :for={_ <- 1..3} />
            </div>
          </:skeleton>
        </.section>

        <.section
          id="minimal-list-item"
          title="Minimal List Item"
          ratio="horizontal"
          rows="search results · episode lists"
        >
          <:live>
            <div class="divide-y divide-border-subtle rounded-md border border-border-subtle bg-bg">
              <Cards.minimal_list_item :for={item <- @list_items} item={item} />
            </div>
          </:live>
          <:skeleton>
            <div class="divide-y divide-border-subtle rounded-md border border-border-subtle bg-bg">
              <Cards.minimal_list_item_skeleton :for={_ <- 1..3} />
            </div>
          </:skeleton>
        </.section>
      </div>

      <section id="page-simulation" class="scroll-mt-6 border-t border-border-subtle bg-bg">
        <div class="mx-auto max-w-7xl px-6 pt-12">
          <p class="font-mono text-xs uppercase tracking-wide text-text-muted">
            Page simulation
          </p>
          <h2 class="mt-2 font-display text-3xl leading-tight tracking-tighter text-text-primary">
            Assembled homepage
          </h2>
          <p class="mt-3 max-w-2xl font-body text-base leading-relaxed text-text-secondary">
            Four rows composed from Stage 3 components. Carousels drag with
            momentum. Cards stagger in on mount.
          </p>
        </div>

        <Rows.row row={%{type: :hero, id: "sim-hero", item: @hero}} />

        <div class="mx-auto max-w-7xl">
          <Rows.row row={
            %{
              type: :continue_watching,
              id: "sim-cw",
              card: :progress_course,
              items: @continue_items
            }
          } />

          <Rows.row row={
            %{
              type: :content,
              id: "sim-popularity",
              title: "Popular this week",
              see_all_href: "#",
              card: :poster_portrait,
              items: @posters
            }
          } />

          <Rows.row row={
            %{
              type: :editorial_spotlight,
              id: "sim-spotlight",
              title: "Editor's picks",
              collection: hd(@collections),
              posters: tl(@posters)
            }
          } />

          <Rows.row row={
            %{
              type: :creator_showcase,
              id: "sim-creators",
              title: "Creators to follow",
              items: @creators
            }
          } />

          <Rows.row row={
            %{
              type: :series,
              id: "sim-series",
              title: "Fieldwork · Season 1",
              see_all_href: "#",
              card: :landscape_episode,
              items: @series_items
            }
          } />

          <Rows.row row={
            %{
              type: :continue_watching,
              id: "sim-cw-empty",
              card: :landscape_episode,
              items: @continue_empty
            }
          } />

          <div
            class="mx-6 mb-16 mt-4 rounded-md border border-dashed border-border-subtle bg-surface/40 p-4 font-mono text-xs text-text-muted"
            data-test="empty-cw-note"
          >
            The empty continue-watching row above renders nothing —
            absolute rule.
          </div>
        </div>
      </section>
    </main>
    """
  end

  # ---------------------------------------------------------------------------
  # Layout helper — one section per variant
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :ratio, :string, required: true
  attr :rows, :string, required: true
  slot :live, required: true
  slot :skeleton, required: true

  defp section(assigns) do
    ~H"""
    <section id={@id} class="scroll-mt-6">
      <div class="mb-6 flex flex-wrap items-baseline justify-between gap-4 border-b border-border-subtle pb-3">
        <div>
          <h2 class="font-display text-2xl leading-tight tracking-tight text-text-primary">
            {@title}
          </h2>
          <p class="mt-1 font-mono text-xs text-text-muted">
            Aspect {@ratio} · {@rows}
          </p>
        </div>
      </div>

      <div class="space-y-10">
        <div>
          <p class="mb-4 font-ui text-sm text-text-secondary">Live</p>
          {render_slot(@live)}
        </div>
        <div>
          <p class="mb-4 font-ui text-sm text-text-secondary">Skeleton</p>
          {render_slot(@skeleton)}
        </div>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Seeded mock data
  # ---------------------------------------------------------------------------

  defp seed_image(seed, w, h),
    do: "https://picsum.photos/seed/marquee-#{seed}/#{w}/#{h}"

  defp posters do
    [
      %{
        id: "p1",
        title: "La Jetée",
        year: 1962,
        duration: "28 min",
        image_url: seed_image("la-jetee", 400, 600),
        progress: 0.35
      },
      %{
        id: "p2",
        title: "Le Mépris",
        year: 1963,
        duration: "1h 43m",
        image_url: seed_image("le-mepris", 400, 600)
      },
      %{
        id: "p3",
        title: "Cléo from 5 to 7",
        year: 1962,
        duration: "1h 30m",
        image_url: seed_image("cleo", 400, 600),
        progress: 0.85
      },
      %{
        id: "p4",
        title: "Pierrot le Fou",
        year: 1965,
        duration: "1h 50m",
        image_url: seed_image("pierrot", 400, 600)
      },
      %{
        id: "p5",
        title: "L'Atalante",
        year: 1934,
        duration: "1h 29m",
        image_url: seed_image("latalante", 400, 600)
      }
    ]
  end

  defp episodes do
    [
      %{
        id: "e1",
        title: "The Long Walk Home",
        series: "Northern Lights · Season 2",
        episode_number: 4,
        duration: "42:18",
        image_url: seed_image("northern-4", 640, 360),
        progress: 0.62
      },
      %{
        id: "e2",
        title: "Inheritance",
        series: "Fieldwork · Season 1",
        episode_number: 7,
        duration: "38:42",
        image_url: seed_image("fieldwork-7", 640, 360)
      },
      %{
        id: "e3",
        title: "Signal to Noise",
        series: "Breakers · Season 3",
        episode_number: 1,
        duration: "51:04",
        image_url: seed_image("breakers-1", 640, 360),
        progress: 0.08
      }
    ]
  end

  defp creators do
    [
      %{
        id: "c1",
        name: "Agnès Duret",
        content_count: 24,
        image_url: seed_image("duret", 400, 400)
      },
      %{
        id: "c2",
        name: "Miles Thornton",
        content_count: 17,
        image_url: seed_image("thornton", 400, 400)
      },
      %{id: "c3", name: "Keiko Abe", content_count: 42, image_url: seed_image("abe", 400, 400)},
      %{
        id: "c4",
        name: "Rafael Sorín",
        content_count: 9,
        image_url: seed_image("sorin", 400, 400)
      }
    ]
  end

  defp collections do
    [
      %{
        id: "col1",
        title: "The Quiet Revolutions",
        film_count: 14,
        curator_note:
          "Fourteen films that found their power in stillness — from Varda's beaches to Hou's back alleys, a meditation on what cinema can hold when it refuses to raise its voice.",
        image_url: seed_image("quiet-revolutions", 900, 600)
      },
      %{
        id: "col2",
        title: "Rochester After Dark",
        film_count: 8,
        curator_note:
          "Eight neo-noirs from the Flower City and its long industrial shadow — Kodak light, lake-effect fog, and a camera that knows every empty diner on East Avenue.",
        image_url: seed_image("rochester-noir", 900, 600)
      }
    ]
  end

  defp courses do
    [
      %{
        id: "co1",
        title: "Cinematography Foundations",
        instructor: "Priya Raman",
        lessons_completed: 6,
        lessons_total: 18,
        percent: 33,
        image_url: seed_image("cinematography", 640, 360)
      },
      %{
        id: "co2",
        title: "Color Grading in DaVinci Resolve",
        instructor: "Tomás Okafor",
        lessons_completed: 12,
        lessons_total: 12,
        percent: 100,
        image_url: seed_image("color-grading", 640, 360)
      },
      %{
        id: "co3",
        title: "Sound Design for Short Film",
        instructor: "Helena Vidar",
        lessons_completed: 2,
        lessons_total: 10,
        percent: 20,
        image_url: seed_image("sound-design", 640, 360)
      }
    ]
  end

  defp list_items do
    [
      %{
        id: "l1",
        title: "Paris, Texas",
        metadata: "1984 · 2h 25m · Drama",
        synopsis:
          "A drifter emerges from the desert and begins a slow reckoning with the family he left behind. Wim Wenders at his most restrained.",
        image_url: seed_image("paris-texas", 200, 300)
      },
      %{
        id: "l2",
        title: "Chungking Express",
        metadata: "1994 · 1h 42m · Romance",
        synopsis:
          "Two Hong Kong cops, two brief affairs, and a pineapple can that keeps expiring. Wong Kar-wai's breakout on neon and longing.",
        image_url: seed_image("chungking", 200, 300)
      },
      %{
        id: "l3",
        title: "Close-Up",
        metadata: "1990 · 1h 38m · Documentary",
        synopsis:
          "A man impersonates a famous director and is caught. Kiarostami then asks the real participants to reenact the story — documentary, fiction, and conscience collapse into each other.",
        image_url: seed_image("close-up", 200, 300)
      }
    ]
  end

  defp hero_item do
    %{
      title: "The Quiet Revolutions",
      byline: "Editor's picks · April",
      synopsis:
        "Fourteen films that found their power in stillness — from Varda's beaches to Hou's back alleys. A month of cinema that refuses to raise its voice.",
      image_url: seed_image("hero-quiet-revolutions", 1600, 900),
      cta_primary: %{label: "Start watching", href: "#"},
      cta_secondary: %{label: "More info", href: "#"}
    }
  end

  defp continue_items do
    [
      %{
        id: "co1",
        title: "Cinematography Foundations",
        instructor: "Priya Raman",
        lessons_completed: 6,
        lessons_total: 18,
        percent: 33,
        image_url: seed_image("cinematography", 640, 360),
        time_remaining: "2h 14m"
      },
      %{
        id: "co3",
        title: "Sound Design for Short Film",
        instructor: "Helena Vidar",
        lessons_completed: 2,
        lessons_total: 10,
        percent: 20,
        image_url: seed_image("sound-design", 640, 360),
        time_remaining: "3h 42m"
      }
    ]
  end

  defp series_items do
    [
      %{
        id: "fw1",
        title: "Pilot",
        series: "Fieldwork",
        episode_number: 1,
        duration: "38:04",
        image_url: seed_image("fieldwork-1", 640, 360),
        progress: 1.0
      },
      %{
        id: "fw2",
        title: "The Map Room",
        series: "Fieldwork",
        episode_number: 2,
        duration: "41:22",
        image_url: seed_image("fieldwork-2", 640, 360),
        progress: 1.0
      },
      %{
        id: "fw3",
        title: "Crossings",
        series: "Fieldwork",
        episode_number: 3,
        duration: "44:18",
        image_url: seed_image("fieldwork-3", 640, 360),
        progress: 0.42,
        current?: true
      },
      %{
        id: "fw4",
        title: "Silt",
        series: "Fieldwork",
        episode_number: 4,
        duration: "39:50",
        image_url: seed_image("fieldwork-4", 640, 360)
      },
      %{
        id: "fw5",
        title: "Inheritance",
        series: "Fieldwork",
        episode_number: 5,
        duration: "38:42",
        image_url: seed_image("fieldwork-5", 640, 360)
      }
    ]
  end
end
