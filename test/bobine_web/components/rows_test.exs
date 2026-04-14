defmodule BobineWeb.Components.RowsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BobineWeb.Components.Rows

  defp poster(id, title \\ "T"),
    do: %{id: id, title: title, year: 2024, duration: "1h", image_url: "x"}

  defp episode(id, attrs \\ %{}) do
    Map.merge(
      %{
        id: id,
        title: "E#{id}",
        series: "Show",
        episode_number: 1,
        duration: "30:00",
        image_url: "x"
      },
      attrs
    )
  end

  defp course(id, attrs \\ %{}) do
    Map.merge(
      %{
        id: id,
        title: "C",
        instructor: "I",
        lessons_completed: 1,
        lessons_total: 10,
        percent: 10,
        image_url: "x"
      },
      attrs
    )
  end

  describe "hero_row/1" do
    test "renders title, byline, synopsis, and CTAs" do
      item = %{
        title: "The Quiet Revolutions",
        byline: "Editor's picks",
        synopsis: "Stillness on film.",
        image_url: "https://example.com/h.jpg",
        cta_primary: %{label: "Start watching", href: "/watch"},
        cta_secondary: %{label: "More info", href: "/info"}
      }

      html = render_component(&Rows.hero_row/1, %{item: item})

      assert html =~ "The Quiet Revolutions"
      assert html =~ "Editor" <> "&#39;" <> "s picks"
      assert html =~ "Stillness on film."
      assert html =~ "Start watching"
      assert html =~ "More info"
      assert html =~ ~s(href="/watch")
      assert html =~ ~s(data-test="row-hero")
      assert html =~ "ken-burns"
    end
  end

  describe "content_row/1" do
    test "renders title, see-all link, and carousel hook" do
      items = for i <- 1..3, do: poster("p#{i}", "Title #{i}")

      html =
        render_component(&Rows.content_row/1, %{
          id: "pop",
          title: "Popular",
          see_all_href: "/browse",
          card: :poster_portrait,
          items: items
        })

      assert html =~ "Popular"
      assert html =~ ~s(data-test="row-content")
      assert html =~ ~s(phx-hook="Carousel")
      assert html =~ ~s(phx-hook="StaggerReveal")
      assert html =~ ~s(data-carousel-track)
      assert html =~ ~s(data-carousel-prev)
      assert html =~ ~s(data-carousel-next)
      assert html =~ ~s(aria-label="Scroll left")
      assert html =~ ~s(aria-label="Scroll right")
      assert html =~ "See all"
      assert html =~ "Title 1"
      assert html =~ "Title 3"
    end

    test "omits see-all link when nil" do
      html =
        render_component(&Rows.content_row/1, %{
          id: "p",
          title: "T",
          see_all_href: nil,
          card: :poster_portrait,
          items: [poster("p1")]
        })

      refute html =~ "See all"
    end

    test "renders each supported card variant" do
      for {variant, item} <- [
            {:poster_portrait, poster("p1")},
            {:landscape_episode, episode("e1")},
            {:progress_course, course("c1")}
          ] do
        html =
          render_component(&Rows.content_row/1, %{
            id: "r-#{variant}",
            title: "T",
            see_all_href: nil,
            card: variant,
            items: [item]
          })

        assert html =~ to_string(item.id)
      end
    end
  end

  describe "continue_watching_row/1" do
    test "renders nothing when items is empty" do
      html =
        render_component(&Rows.continue_watching_row/1, %{
          id: "cw",
          card: :progress_course,
          items: []
        })

      assert String.trim(html) == ""
    end

    test "renders dismiss button and time remaining when items present" do
      items = [
        course("c1", %{time_remaining: "2h 14m"}),
        course("c2", %{time_remaining: "45m"})
      ]

      html =
        render_component(&Rows.continue_watching_row/1, %{
          id: "cw",
          card: :progress_course,
          items: items
        })

      assert html =~ ~s(data-test="row-continue-watching")
      assert html =~ ~s(data-test="dismiss-c1")
      assert html =~ ~s(phx-click="dismiss_continue")
      assert html =~ "2h 14m left"
      assert html =~ "45m left"
    end
  end

  describe "series_row/1" do
    test "marks the current episode with accent ring" do
      items = [
        episode("e1"),
        episode("e2", %{current?: true}),
        episode("e3")
      ]

      html =
        render_component(&Rows.series_row/1, %{
          id: "s",
          title: "Season 1",
          card: :landscape_episode,
          items: items
        })

      assert html =~ ~s(data-test="row-series")
      assert html =~ ~s(data-test="series-current-e2")
      assert html =~ "ring-accent"
    end
  end

  describe "creator_showcase_row/1" do
    test "renders creator cards with wider gap and no see-all" do
      items = [
        %{id: "c1", name: "Agnès", content_count: 24, image_url: "x"},
        %{id: "c2", name: "Miles", content_count: 17, image_url: "x"}
      ]

      html =
        render_component(&Rows.creator_showcase_row/1, %{
          id: "cr",
          title: "Creators",
          items: items
        })

      assert html =~ ~s(data-test="row-creator-showcase")
      assert html =~ "gap-8"
      assert html =~ "Agnès"
      refute html =~ "See all"
    end
  end

  describe "editorial_spotlight_row/1" do
    test "renders collection followed by poster cards" do
      collection = %{
        id: "col1",
        title: "Revolutions",
        film_count: 10,
        curator_note: "note",
        image_url: "x"
      }

      posters = for i <- 1..3, do: poster("p#{i}", "P#{i}")

      html =
        render_component(&Rows.editorial_spotlight_row/1, %{
          id: "sp",
          title: "Spotlight",
          collection: collection,
          posters: posters
        })

      assert html =~ ~s(data-test="row-editorial-spotlight")
      assert html =~ "Revolutions"
      assert html =~ "P1"
      assert html =~ "P3"
    end
  end

  describe "row/1 dispatcher" do
    test "dispatches :hero" do
      html =
        render_component(&Rows.row/1, %{
          row: %{
            type: :hero,
            id: "h",
            item: %{
              title: "T",
              byline: "B",
              synopsis: "S",
              image_url: "x",
              cta_primary: %{label: "A", href: "#"},
              cta_secondary: %{label: "B", href: "#"}
            }
          }
        })

      assert html =~ ~s(data-test="row-hero")
    end

    test "dispatches :content" do
      html =
        render_component(&Rows.row/1, %{
          row: %{
            type: :content,
            id: "c",
            title: "T",
            card: :poster_portrait,
            items: [poster("p1")]
          }
        })

      assert html =~ ~s(data-test="row-content")
    end

    test "dispatches :continue_watching and skips when empty" do
      empty =
        render_component(&Rows.row/1, %{
          row: %{
            type: :continue_watching,
            id: "cw",
            card: :landscape_episode,
            items: []
          }
        })

      assert String.trim(empty) == ""

      filled =
        render_component(&Rows.row/1, %{
          row: %{
            type: :continue_watching,
            id: "cw",
            card: :landscape_episode,
            items: [episode("e1")]
          }
        })

      assert filled =~ ~s(data-test="row-continue-watching")
    end

    test "dispatches :series, :creator_showcase, :editorial_spotlight" do
      series =
        render_component(&Rows.row/1, %{
          row: %{
            type: :series,
            id: "s",
            title: "T",
            card: :landscape_episode,
            items: [episode("e1")]
          }
        })

      assert series =~ ~s(data-test="row-series")

      creators =
        render_component(&Rows.row/1, %{
          row: %{
            type: :creator_showcase,
            id: "cr",
            title: "T",
            items: [%{id: "c1", name: "A", content_count: 1, image_url: "x"}]
          }
        })

      assert creators =~ ~s(data-test="row-creator-showcase")

      spotlight =
        render_component(&Rows.row/1, %{
          row: %{
            type: :editorial_spotlight,
            id: "sp",
            title: "T",
            collection: %{
              id: "col",
              title: "C",
              film_count: 1,
              curator_note: "n",
              image_url: "x"
            },
            posters: [poster("p1")]
          }
        })

      assert spotlight =~ ~s(data-test="row-editorial-spotlight")
    end
  end
end
