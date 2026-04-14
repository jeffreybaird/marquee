defmodule BobineWeb.Components.CardsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BobineWeb.Components.Cards

  describe "poster_portrait/1" do
    test "renders title, image, and card link" do
      item = %{
        id: "p1",
        title: "La Jetée",
        year: 1962,
        duration: "28 min",
        image_url: "https://example.com/p.jpg"
      }

      html = render_component(&Cards.poster_portrait/1, %{item: item, href: "/watch/p1"})

      assert html =~ "La Jetée"
      assert html =~ "https://example.com/p.jpg"
      assert html =~ ~s(data-test="card-poster-p1")
      assert html =~ ~s(href="/watch/p1")
      assert html =~ "aspect-[2/3]"
    end

    test "renders progress bar when progress present" do
      item = %{
        id: "p2",
        title: "T",
        year: 2024,
        duration: "1h",
        image_url: "x",
        progress: 0.42
      }

      html = render_component(&Cards.poster_portrait/1, %{item: item})

      assert html =~ "width: 42%"
      assert html =~ "bg-accent"
    end

    test "omits progress bar when progress absent" do
      item = %{id: "p3", title: "T", year: 2024, duration: "1h", image_url: "x"}
      html = render_component(&Cards.poster_portrait/1, %{item: item})

      refute html =~ "style=\"width:"
    end
  end

  describe "poster_portrait_skeleton/1" do
    test "renders skeleton with matching aspect ratio" do
      html = render_component(&Cards.poster_portrait_skeleton/1, %{})

      assert html =~ "aspect-[2/3]"
      assert html =~ ~s(data-test="card-poster-skeleton")
      assert html =~ "animate-[shimmer"
    end
  end

  describe "landscape_episode/1" do
    test "renders episode badge, duration, title, and series" do
      item = %{
        id: "e1",
        title: "Pilot",
        series: "Northern Lights",
        episode_number: 1,
        duration: "42:00",
        image_url: "https://example.com/e.jpg"
      }

      html = render_component(&Cards.landscape_episode/1, %{item: item})

      assert html =~ "EP 1"
      assert html =~ "42:00"
      assert html =~ "Pilot"
      assert html =~ "Northern Lights"
      assert html =~ ~s(data-test="card-episode-e1")
      assert html =~ "aspect-video"
    end

    test "includes progress bar when progress present" do
      item = %{
        id: "e2",
        title: "t",
        series: "s",
        episode_number: 2,
        duration: "10:00",
        image_url: "x",
        progress: 0.5
      }

      html = render_component(&Cards.landscape_episode/1, %{item: item})
      assert html =~ "width: 50%"
    end
  end

  describe "landscape_episode_skeleton/1" do
    test "renders skeleton with video aspect" do
      html = render_component(&Cards.landscape_episode_skeleton/1, %{})
      assert html =~ "aspect-video"
      assert html =~ ~s(data-test="card-episode-skeleton")
    end
  end

  describe "creator_identity/1" do
    test "renders name, content count, and square aspect" do
      item = %{id: "c1", name: "Agnès Duret", content_count: 24, image_url: "x"}
      html = render_component(&Cards.creator_identity/1, %{item: item})

      assert html =~ "Agnès Duret"
      assert html =~ "24 titles"
      assert html =~ "aspect-square"
      assert html =~ ~s(data-test="card-creator-c1")
      assert html =~ "View channel"
    end
  end

  describe "creator_identity_skeleton/1" do
    test "renders square skeleton" do
      html = render_component(&Cards.creator_identity_skeleton/1, %{})
      assert html =~ "aspect-square"
      assert html =~ ~s(data-test="card-creator-skeleton")
    end
  end

  describe "collection_editorial/1" do
    test "renders title, film count, curator note, and 3:2 aspect" do
      item = %{
        id: "col1",
        title: "The Quiet Revolutions",
        film_count: 14,
        curator_note: "A curated set.",
        image_url: "x"
      }

      html = render_component(&Cards.collection_editorial/1, %{item: item})

      assert html =~ "The Quiet Revolutions"
      assert html =~ "14 films"
      assert html =~ "A curated set."
      assert html =~ "aspect-[3/2]"
      assert html =~ ~s(data-test="card-collection-col1")
    end
  end

  describe "collection_editorial_skeleton/1" do
    test "renders 3:2 skeleton" do
      html = render_component(&Cards.collection_editorial_skeleton/1, %{})
      assert html =~ "aspect-[3/2]"
      assert html =~ ~s(data-test="card-collection-skeleton")
    end
  end

  describe "progress_course/1" do
    test "renders title, instructor, lesson string, and progress percent" do
      item = %{
        id: "co1",
        title: "Cinematography",
        instructor: "Priya Raman",
        lessons_completed: 6,
        lessons_total: 18,
        percent: 33,
        image_url: "x"
      }

      html = render_component(&Cards.progress_course/1, %{item: item})

      assert html =~ "Cinematography"
      assert html =~ "Priya Raman"
      assert html =~ "Lesson 6 of 18"
      assert html =~ "33%"
      assert html =~ "width: 33%"
      assert html =~ ~s(aria-valuenow="33")
      assert html =~ ~s(data-test="card-course-co1")
    end

    test "switches to success color at 100 percent" do
      item = %{
        id: "co2",
        title: "Done",
        instructor: "x",
        lessons_completed: 10,
        lessons_total: 10,
        percent: 100,
        image_url: "x"
      }

      html = render_component(&Cards.progress_course/1, %{item: item})
      assert html =~ "bg-success"
      assert html =~ "100%"
    end
  end

  describe "progress_course_skeleton/1" do
    test "renders skeleton with video aspect" do
      html = render_component(&Cards.progress_course_skeleton/1, %{})
      assert html =~ "aspect-video"
      assert html =~ ~s(data-test="card-course-skeleton")
    end
  end

  describe "minimal_list_item/1" do
    test "renders title, metadata, synopsis, and chevron" do
      item = %{
        id: "l1",
        title: "Paris, Texas",
        metadata: "1984 · 2h 25m",
        synopsis: "A drifter returns.",
        image_url: "x"
      }

      html = render_component(&Cards.minimal_list_item/1, %{item: item})

      assert html =~ "Paris, Texas"
      assert html =~ "1984 · 2h 25m"
      assert html =~ "A drifter returns."
      assert html =~ "hero-chevron-right"
      assert html =~ ~s(data-test="card-list-l1")
    end
  end

  describe "minimal_list_item_skeleton/1" do
    test "renders horizontal skeleton" do
      html = render_component(&Cards.minimal_list_item_skeleton/1, %{})
      assert html =~ ~s(data-test="card-list-skeleton")
      assert html =~ "animate-[shimmer"
    end
  end

  describe "shimmer/1" do
    test "renders decorative overlay marked aria-hidden" do
      html = render_component(&Cards.shimmer/1, %{})
      assert html =~ ~s(aria-hidden="true")
      assert html =~ "animate-[shimmer"
    end
  end
end
