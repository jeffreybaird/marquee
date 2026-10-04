defmodule MarqueeWeb.Viewer.SubscriberDemoCatalogTest do
  use MarqueeWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Marquee.{Engagement, Repo, SubscriberDemo, Viewers}

  test "curated demo hides legacy rows and seeds only curated activity while preserving existing content" do
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

    legacy =
      insert(:video,
        organization: org,
        title: "Legacy unrelated footage",
        published: true,
        mux_status: "ready",
        duration: 180.0,
        inserted_at: ~U[2020-01-01 00:00:00Z]
      )

    row =
      insert(:row,
        organization: org,
        title: "Legacy collection",
        source_type: :curated,
        visible: true
      )

    insert(:row_item, organization: org, row: row, video: legacy)
    {:ok, catalog} = SubscriberDemo.seed_catalog(org)
    conn = build_conn() |> Map.put(:host, "the-workshop.localhost") |> post("/demo/subscriber")
    viewer = Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token))
    {:ok, home, _} = live(recycle(conn), "/")
    refute has_element?(home, "[data-test=content-row-#{row.id}]")
    refute render(home) =~ legacy.title
    assert render(home) =~ catalog.series.title
    curated_ids = MapSet.new(catalog.videos, & &1.id)
    history = Engagement.list_watch_history(org, viewer).results
    assert history != []
    assert Enum.all?(history, &MapSet.member?(curated_ids, &1.video_id))

    assert Enum.all?(
             Engagement.list_continue_watching(org, viewer).results,
             &MapSet.member?(curated_ids, &1.video.id)
           )

    assert Repo.get!(Marquee.Content.Video, legacy.id).deleted_at == nil
    assert Repo.get!(Marquee.Catalog.Row, row.id).visible

    regular = insert(:subscribed_viewer, organization: org)
    {:ok, normal_home, _} = live(conn_for_viewer(regular), "/")
    assert render(normal_home) =~ legacy.title
  end
end
