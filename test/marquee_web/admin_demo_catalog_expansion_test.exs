defmodule MarqueeWeb.AdminDemoCatalogExpansionTest do
  use MarqueeWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest
  alias Marquee.{AdminDemo, AdminDemoFixtures, Content, Repo}

  alias Marquee.Catalog.HeroSlide
  alias Marquee.Content.{Collection, Series, Video}

  @moduletag :tmp_dir
  @host "demo-marquee.example.test"

  setup %{tmp_dir: dir} do
    path = Path.join(dir, "catalog.json")
    original = Application.fetch_env(:marquee, :admin_demo)
    File.write!(path, Jason.encode!(AdminDemoFixtures.catalog_manifest()))
    Application.put_env(:marquee, :admin_demo, enabled: true, host: @host, catalog_path: path)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end)

    %{path: path}
  end

  test "reviewed Wanderlust catalog has sixty unique attributed clips and preserves prior media identities" do
    manifest = "priv/admin_demo/wanderlust_catalog.json" |> File.read!() |> Jason.decode!()
    clips = manifest["clips"]
    assert manifest["version"] == "wanderlust-v2"
    assert length(clips) == 60
    assert Enum.count(clips, & &1["initial"]) == 48

    for key <- ["slug", "mux_asset_id", "mux_playback_id", "source_url"] do
      assert clips |> Enum.map(& &1[key]) |> Enum.uniq() |> length() == 60
    end

    for clip <- clips,
        key <- [
          "title",
          "description",
          "creator_name",
          "creator_url",
          "license_url",
          "source_url"
        ] do
      assert is_binary(clip[key]) and String.trim(clip[key]) != ""
    end

    grouped = Enum.group_by(clips, & &1["collection"])

    assert Enum.sort(Map.keys(grouped)) == [
             "City journeys",
             "Coastal escapes",
             "Food & culture",
             "Wild horizons"
           ]

    for {_name, group} <- grouped do
      assert length(group) == 15
      assert Enum.count(group, & &1["initial"]) == 12
    end

    baseline = "test/fixtures/admin_demo/v1_clip_identity.json" |> File.read!() |> Jason.decode!()

    for identity <- baseline do
      clip = Enum.find(clips, &(&1["slug"] == identity["slug"]))
      assert Map.take(clip, Map.keys(identity)) == identity
    end

    config = Application.fetch_env!(:marquee, :admin_demo)

    Application.put_env(
      :marquee,
      :admin_demo,
      Keyword.put(config, :catalog_path, "priv/admin_demo/wanderlust_catalog.json")
    )

    {:ok, _} = AdminDemo.configure_host(@host)
    {:ok, demo} = AdminDemo.start_session()

    hero_slugs =
      Repo.all(
        from h in HeroSlide,
          join: v in Video,
          on: h.video_id == v.id,
          where: h.organization_id == ^demo.organization.id,
          order_by: h.position,
          select: v.slug
      )

    assert hero_slugs == ["bali-from-above", "venice-by-gondola", "along-the-grand-canal"]
  end

  test "new sessions and reset seed the full catalog while an existing visitor keeps edits until reset",
       %{path: path} do
    {:ok, _} = AdminDemo.configure_host(@host)
    {:ok, old} = AdminDemo.start_session()
    {:ok, %{scope: scope}} = AdminDemo.get_session(old.token)
    old_video = hd(Content.list_videos(old.organization).results)
    assert {:ok, _} = Content.update_video(scope, old_video, %{title: "Keep my current edit"})
    File.write!(path, Jason.encode!(AdminDemoFixtures.expanded_catalog_manifest()))
    {:ok, fresh} = AdminDemo.start_session()
    assert_catalog(fresh.organization.id)
    assert Repo.get!(Video, old_video.id).title == "Keep my current edit"

    assert Repo.aggregate(
             from(v in Video, where: v.organization_id == ^old.organization.id),
             :count
           ) == 3

    {:ok, replacement} = AdminDemo.reset_session(old.token)
    assert_catalog(replacement.organization.id)
    assert {:error, :revoked} = AdminDemo.get_session(old.token)
    assert Repo.get!(Video, old_video.id).title == "Keep my current edit"
    {:ok, %{scope: scope}} = AdminDemo.get_session(replacement.token)
    extra = Enum.find(AdminDemoFixtures.expanded_catalog_manifest().clips, &(!&1.initial))
    assert {:ok, added} = AdminDemo.add_sample_clip(scope, extra.slug)
    assert added.mux_asset_id == nil

    assert Repo.aggregate(
             from(v in Video, where: v.organization_id == ^replacement.organization.id),
             :count
           ) == 49
  end

  test "sandbox browse shows all forty-eight initial clips and an approved added clip", %{
    path: path
  } do
    File.write!(path, Jason.encode!(AdminDemoFixtures.expanded_catalog_manifest()))
    {:ok, _} = AdminDemo.configure_host(@host)
    {:ok, demo} = AdminDemo.start_session()

    conn =
      build_conn() |> Map.put(:host, @host) |> init_test_session(%{admin_demo_token: demo.token})

    {:ok, _view, html} = live(conn, "/browse")

    for clip <- Enum.filter(AdminDemoFixtures.expanded_catalog_manifest().clips, & &1.initial) do
      assert html =~ clip.title
    end

    {:ok, %{scope: scope}} = AdminDemo.get_session(demo.token)
    extra = Enum.find(AdminDemoFixtures.expanded_catalog_manifest().clips, &(!&1.initial))
    {:ok, _} = AdminDemo.add_sample_clip(scope, extra.slug)

    refreshed =
      build_conn() |> Map.put(:host, @host) |> init_test_session(%{admin_demo_token: demo.token})

    {:ok, _view, html} = live(refreshed, "/browse")
    assert html =~ extra.title

    assert html
           |> Floki.parse_document!()
           |> Floki.find("[data-test=sv-browse-grid] > [data-test^=sv-card-]")
           |> length() == 49
  end

  test "ordinary tenant browse keeps the existing twenty-four item limit" do
    org = insert(:organization)

    for n <- 1..30,
        do: insert(:video, organization: org, title: "Ordinary clip #{n}", published: true)

    {:ok, view, _html} = live(build_conn(), "/browse?org=#{org.slug}")
    html = render(view)
    titles = Regex.scan(~r/Ordinary clip \d+/, html) |> Enum.uniq()
    assert length(titles) == 24
  end

  defp assert_catalog(org_id) do
    assert Repo.aggregate(from(v in Video, where: v.organization_id == ^org_id), :count) == 48
    assert Repo.aggregate(from(c in Collection, where: c.organization_id == ^org_id), :count) == 4
    assert Repo.aggregate(from(s in Series, where: s.organization_id == ^org_id), :count) == 4
  end
end
