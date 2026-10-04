defmodule MarqueeWeb.Viewer.SubscriberDemoHeroTest do
  use MarqueeWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Marquee.SubscriberDemo

  test "Explore series opens the series while Play episode opens its first video" do
    previous = Application.fetch_env(:marquee, :subscriber_demo_catalog)

    Application.put_env(
      :marquee,
      :subscriber_demo_catalog,
      Marquee.SubscriberDemoFixtures.catalog_manifest()
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:marquee, :subscriber_demo_catalog, value)
        :error -> Application.delete_env(:marquee, :subscriber_demo_catalog)
      end
    end)

    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})
    {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    conn = build_conn() |> Map.put(:host, "the-workshop.localhost") |> post("/demo/subscriber")
    {:ok, home, _} = live(recycle(conn), "/")

    assert has_element?(
             home,
             "[data-test=hero-primary-cta-0][href='/watch/#{hd(catalog.videos).id}']",
             "Play episode"
           )

    assert has_element?(
             home,
             "[data-test=hero-secondary-cta-0][href='/series/#{catalog.series.slug}']",
             "Explore series"
           )
  end
end
