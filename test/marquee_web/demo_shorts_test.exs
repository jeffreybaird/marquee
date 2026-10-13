defmodule MarqueeWeb.DemoShortsTest do
  use MarqueeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.{AdminDemo, Content, DemoSeeder, Release, Repo, SubscriberDemo, Viewers}
  alias Marquee.Content.Video
  alias Marquee.Workers.MuxAssetCleanup
  alias MarqueeWeb.Plugs.RateLimit

  @moduletag :tmp_dir
  @host "shorts-demo.example.test"

  setup %{tmp_dir: dir} do
    travel = Marquee.AdminDemoFixtures.catalog_manifest()

    workshop = Marquee.SubscriberDemoFixtures.catalog_manifest()

    path = Path.join(dir, "travel.json")
    File.write!(path, Jason.encode!(travel))

    portraits = %{
      travel:
        travel.clips
        |> Enum.take(3)
        |> Enum.map(&portrait_fixture/1),
      workshop:
        workshop
        |> Enum.take(2)
        |> Enum.map(&portrait_fixture/1)
    }

    changes = [
      demo_shorts_catalog: portraits,
      admin_demo: [enabled: true, host: @host, catalog_path: path],
      subscriber_demo_catalog: workshop,
      rate_limit_disabled: true
    ]

    previous = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end

      RateLimit.reset()
    end)

    {:ok, _} = AdminDemo.configure_host(@host)
    %{travel: portraits.travel, workshop: portraits.workshop}
  end

  test "private admin clones curate dedicated portrait footage without relabeling longform", %{
    travel: travel
  } do
    {:ok, demo} = start_demo()
    org = Repo.get!(Organization, demo.organization.id)
    assert org.shorts_feed_enabled
    assert org.shorts_feed_access == "subscribers_only"
    items = Content.list_short_feed_items(org).results
    expected = travel
    assert Enum.map(items, & &1.video.slug) == Enum.map(expected, & &1.slug)
    assert Enum.all?(items, &(&1.video.aspect_ratio == "9:16"))
    assert Enum.all?(items, &is_nil(&1.video.mux_asset_id))
    assert Enum.map(items, & &1.video.mux_playback_id) == Enum.map(expected, & &1.mux_playback_id)
    landscape = Repo.get_by!(Video, organization_id: org.id, slug: "travel-fixture-2")
    assert landscape.aspect_ratio != "9:16"
    assert {:ok, %{results: playable}} = Content.list_short_feed(org)
    assert Enum.map(playable, & &1.id) == Enum.map(items, & &1.video_id)
  end

  test "admin demo can manage Shorts and open a playable private preview" do
    conn = entered_conn()
    {:ok, %{scope: scope}} = AdminDemo.get_session(get_session(conn, :admin_demo_token))
    {:ok, view, _} = live(recycle(conn), "/admin/shorts")
    assert has_element?(view, ~s([data-test="admin-nav-shorts"][aria-current="page"]))
    assert has_element?(view, ~s([data-test="shorts-enabled-toggle"][aria-checked="true"]))
    items = Content.list_short_feed_items(scope.organization).results
    assert length(items) == 3
    last = List.last(items)
    view |> element(~s([data-test="shorts-move-up-#{last.id}"])) |> render_click()
    assert Enum.at(Content.list_short_feed_items(scope.organization).results, 1).id == last.id
    {:ok, preview, _} = live(recycle(conn), "/shorts")

    assert has_element?(
             preview,
             ~s(article[data-video-id="#{last.video_id}"][data-playback-id="#{last.video.mux_playback_id}"])
           )

    assert render(preview) =~ last.video.mux_playback_id
    foreign = insert(:video, aspect_ratio: "9:16", duration: 30.0)
    refute render(preview) =~ foreign.mux_playback_id
    render_click(view, "add_video", %{"video-id" => foreign.id})

    assert Enum.map(Content.list_short_feed_items(scope.organization).results, & &1.video_id) ==
             [hd(items).video_id, last.video_id, Enum.at(items, 1).video_id]

    view |> element(~s([data-test="shorts-enabled-toggle"])) |> render_click()
    refute Repo.get!(Organization, scope.organization.id).shorts_feed_enabled
  end

  test "reset creates a fresh isolated feed and cannot delete shared portrait assets", %{
    travel: travel
  } do
    {:ok, first} = start_demo()
    {:ok, second} = start_demo()
    second_items = Content.list_short_feed_items(second.organization).results
    {:ok, %{scope: first_scope}} = AdminDemo.get_session(first.token)
    first_item = hd(Content.list_short_feed_items(first.organization).results)
    assert :ok = Content.remove_short_feed_item(first_scope, first_item)
    {:ok, replacement} = AdminDemo.reset_session(first.token)
    assert length(Content.list_short_feed_items(replacement.organization).results) == 3
    assert Content.list_short_feed_items(second.organization).results == second_items
    refute replacement.organization.id == first.organization.id
    real = insert(:organization)

    for clip <- travel do
      assert AdminDemo.protected_asset?(clip.mux_asset_id)

      assert {:cancel, :demo_forbidden} =
               MuxAssetCleanup.perform(%Oban.Job{
                 args: %{"organization_id" => real.id, "mux_asset_id" => clip.mux_asset_id}
               })
    end
  end

  test "Workshop provisions portrait Shorts and reseeding preserves operator settings and order",
       %{
         workshop: workshop
       } do
    assert {:ok, catalog} = DemoSeeder.seed_subscriber_demo()
    org = catalog.organization
    assert org.shorts_feed_enabled
    assert org.shorts_feed_access == "subscribers_only"
    items = Content.list_short_feed_items(org).results

    assert Enum.map(items, & &1.video.slug) ==
             workshop |> Enum.filter(&(&1.aspect_ratio == "9:16")) |> Enum.map(& &1.slug)

    assert Enum.all?(items, &(&1.video.aspect_ratio == "9:16"))
    assert Enum.all?(items, &is_nil(&1.video.mux_asset_id))
    assert Enum.all?(catalog.videos, &(not String.starts_with?(&1.slug, "short-")))
    assert Enum.all?(items, &(&1.video.id in org.features["subscriber_demo_video_ids"]))

    Repo.update!(
      Ecto.Changeset.change(org, shorts_feed_enabled: false, shorts_feed_access: "public")
    )

    [first, last] = items
    Repo.update!(Ecto.Changeset.change(first, position: 100))
    Repo.update!(Ecto.Changeset.change(last, position: 0))
    assert {:ok, repeated} = DemoSeeder.seed_subscriber_demo()
    refute repeated.organization.shorts_feed_enabled
    assert repeated.organization.shorts_feed_access == "public"
    assert Enum.map(Content.list_short_feed_items(org).results, & &1.id) == [last.id, first.id]
    assert repeated.organization.id == org.id
  end

  test "subscriber demo sees playable portrait Shorts and excludes non-demo and foreign clips" do
    {:ok, catalog} = DemoSeeder.seed_subscriber_demo()
    org = catalog.organization
    foreign = insert(:video, aspect_ratio: "9:16", duration: 30.0)
    own = insert(:video, organization: org, aspect_ratio: "9:16", duration: 30.0)
    membership = insert(:membership, organization: org, role: :owner) |> Repo.preload(:user)
    scope = Scope.for_user(membership.user)
    scope = Scope.with_organization(scope, org, membership)
    assert {:ok, _} = Content.add_short_feed_video(scope, own)
    conn = build_conn() |> Map.put(:host, "#{org.slug}.localhost") |> post("/demo/subscriber")
    {:ok, view, _} = live(recycle(conn), "/shorts")
    assert has_element?(view, ~s([data-test="nav-shorts"]))

    for item <- Content.list_short_feed_items(org).results, item.video_id != own.id do
      assert has_element?(
               view,
               ~s(article[data-video-id="#{item.video_id}"][data-playback-id="#{item.video.mux_playback_id}"])
             )

      assert render(view) =~ item.video.mux_playback_id
    end

    refute render(view) =~ own.mux_playback_id
    refute render(view) =~ foreign.mux_playback_id
    assert SubscriberDemo.enabled?(org)
  end

  defp start_demo do
    Oban.Testing.with_testing_mode(:manual, fn -> AdminDemo.start_session() end)
  end

  test "deployment appends missing Workshop portrait playback without refreshing an initialized catalog" do
    org = insert(:organization, slug: "the-workshop", features: %{"subscriber_demo" => true})

    original =
      insert(:video,
        organization: org,
        slug: "workshop-episode-1",
        title: "Operator edited lesson",
        published: true
      )

    theme = insert(:theme, organization: org, background: "#123456")

    org =
      Repo.update!(
        Ecto.Changeset.change(org,
          features: %{
            "subscriber_demo" => true,
            "subscriber_demo_video_ids" => [original.id],
            "subscriber_demo_series_slug" => "inside-the-workshop"
          }
        )
      )

    Application.put_env(:marquee, :subscriber_demo_catalog, [])
    assert {:ok, _} = Release.seed_missing_demo_content()
    updated = Repo.get!(Organization, org.id)
    items = Content.list_short_feed_items(updated).results
    assert length(items) == 2

    assert updated.features["subscriber_demo_video_ids"] == [
             original.id | Enum.map(items, & &1.video_id)
           ]

    assert Repo.get!(Video, original.id).title == "Operator edited lesson"
    assert Repo.get!(theme.__struct__, theme.id).background == "#123456"
    refute Repo.get_by(Video, organization_id: org.id, slug: "workshop-episode-2")
    conn = build_conn() |> Map.put(:host, "#{org.slug}.localhost") |> post("/demo/subscriber")
    assert redirected_to(conn) == "/"
    viewer = Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token))
    assert SubscriberDemo.demo_viewer?(viewer)
    assert viewer.organization_id == org.id
    {:ok, view, _} = live(recycle(conn), "/shorts")

    for item <- items do
      assert has_element?(
               view,
               ~s(article[data-video-id="#{item.video_id}"][data-playback-id="#{item.video.mux_playback_id}"])
             )
    end

    Repo.update!(
      Ecto.Changeset.change(updated,
        features: Map.put(updated.features, "subscriber_demo_video_ids", [])
      )
    )

    Application.put_env(:marquee, :demo_shorts_catalog, %{})
    assert {:ok, _} = Release.seed_missing_demo_content()
    assert Repo.get!(Organization, org.id).features["subscriber_demo_video_ids"] == []
  end

  defp portrait_fixture(clip) do
    Map.merge(clip, %{
      slug: "short-" <> clip.slug,
      mux_playback_id: "portrait-" <> clip.mux_playback_id,
      mux_asset_id: "portrait-" <> clip.mux_asset_id,
      creator_name: "Portrait fixture creator",
      creator_url: "https://media.example.test/portrait-creator",
      license_url: "https://media.example.test/license",
      aspect_ratio: "9:16",
      duration: 20.0
    })
  end

  defp entered_conn do
    build_conn()
    |> Map.put(:host, @host)
    |> put_private(:plug_skip_csrf_protection, true)
    |> get("/demo/admin")
    |> recycle()
    |> post("/demo/admin")
  end
end
