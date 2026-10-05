defmodule MarqueeFeatures.Steps.AdminDemo do
  @moduledoc "Acceptance contract for independent private operator workspaces."
  use Cucumberex.DSL
  @endpoint MarqueeWeb.Endpoint
  import ExUnit.Assertions
  import Ecto.Query
  alias Marquee.{AdminDemo, Content, Podcasts, Repo, Viewers}

  alias Marquee.Accounts.Organization
  alias Marquee.Content.Video
  alias Marquee.Podcasts.Show
  alias Marquee.Viewers.{Viewer, ViewerToken}

  when_("a Wanderlust visitor returns to entry after their private session expires", fn world ->
    import Phoenix.ConnTest
    import Plug.Conn, only: [get_session: 2, put_private: 3]
    original = Application.fetch_env(:marquee, :admin_demo)

    path =
      Path.join(
        System.tmp_dir!(),
        "admin-demo-recovery-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))

    Application.put_env(:marquee, :admin_demo,
      enabled: true,
      host: "recovery-demo.example.test",
      catalog_path: path
    )

    try do
      {:ok, _} = AdminDemo.configure_host("recovery-demo.example.test")

      started =
        build_conn()
        |> Map.put(:host, "recovery-demo.example.test")
        |> put_private(:plug_skip_csrf_protection, true)
        |> get("/demo/admin")
        |> recycle()
        |> post("/demo/admin")

      token = get_session(started, :admin_demo_token)
      {:ok, %{session: session}} = AdminDemo.get_session(token)

      Repo.update!(
        Ecto.Changeset.change(session, expires_at: DateTime.add(DateTime.utc_now(), -1))
      )

      entry = started |> recycle() |> get("/demo/admin")
      assert html_response(entry, 200) =~ "admin-demo-entry-form"
      fresh = entry |> recycle() |> post("/demo/admin")
      assert redirected_to(fresh) == "/admin"
      fresh_token = get_session(fresh, :admin_demo_token)
      refute fresh_token == token
      assert {:ok, %{scope: scope}} = AdminDemo.get_session(fresh_token)
      repeated = fresh |> recycle() |> post("/demo/admin")

      Map.merge(world, %{
        recovered_org_id: scope.organization.id,
        recovered_token: fresh_token,
        repeated_token: get_session(repeated, :admin_demo_token)
      })
    after
      File.rm(path)

      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end
  end)

  then_("beginning again creates one fresh workspace and repeated entry reuses it", fn world ->
    assert world.repeated_token == world.recovered_token

    assert Repo.get!(Organization, world.recovered_org_id).demo_kind ==
             :admin_sandbox

    assert Repo.aggregate(
             from(o in Organization, where: o.demo_kind == :admin_sandbox),
             :count
           ) == 2

    world
  end)

  when_("a Wanderlust visitor manages a sample member and a local podcast", fn world ->
    original = Application.fetch_env(:marquee, :admin_demo)

    path =
      Path.join(
        System.tmp_dir!(),
        "admin-demo-members-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))

    Application.put_env(:marquee, :admin_demo,
      enabled: true,
      host: "members-demo.example.test",
      catalog_path: path
    )

    try do
      {:ok, _} = AdminDemo.configure_host("members-demo.example.test")
      {:ok, demo} = AdminDemo.start_session()
      {:ok, %{scope: scope}} = AdminDemo.get_session(demo.token)
      viewers = Viewers.list_viewers(demo.organization).results
      assert length(viewers) == 6
      viewer = Enum.find(viewers, &(&1.status == :active))
      {:ok, _} = Viewers.suspend_viewer(scope, viewer)
      shows = Repo.all(from s in Show, where: s.organization_id == ^demo.organization.id)
      assert length(shows) == 2
      show = hd(shows)
      {:ok, _} = Podcasts.update_show(scope, show, %{title: "My local travel show"})
      Map.merge(world, %{sample_member_id: viewer.id, sample_show_id: show.id})
    after
      File.rm(path)

      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end
  end)

  then_(
    "the local changes persist without viewer credentials or remote podcast feeds",
    fn world ->
      viewer = Repo.get!(Viewer, world.sample_member_id)
      show = Repo.get!(Show, world.sample_show_id)
      assert viewer.status == :suspended
      assert viewer.hashed_password == nil
      refute Repo.exists?(from t in ViewerToken, where: t.viewer_id == ^viewer.id)
      assert show.title == "My local travel show"
      assert show.source_type == "direct_upload"
      assert show.remote_feed_url == nil
      world
    end
  )

  when_("the Wanderlust catalog expands for a new and a reset visitor", fn world ->
    original = Application.fetch_env(:marquee, :admin_demo)

    path =
      Path.join(
        System.tmp_dir!(),
        "admin-demo-expanded-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))

    Application.put_env(:marquee, :admin_demo,
      enabled: true,
      host: "expanded.example.test",
      catalog_path: path
    )

    try do
      {:ok, _} = AdminDemo.configure_host("expanded.example.test")
      {:ok, old} = AdminDemo.start_session()
      manifest = Marquee.AdminDemoFixtures.expanded_catalog_manifest()
      File.write!(path, Jason.encode!(manifest))
      {:ok, fresh} = AdminDemo.start_session()
      {:ok, reset} = AdminDemo.reset_session(old.token)

      counts =
        for org <- [fresh.organization, reset.organization],
            do: Repo.aggregate(from(v in Video, where: v.organization_id == ^org.id), :count)

      {:ok, %{scope: scope}} = AdminDemo.get_session(reset.token)
      extra = Enum.find(manifest.clips, &(!&1.initial))
      {:ok, video} = AdminDemo.add_sample_clip(scope, extra.slug)

      Map.merge(world, %{
        expanded_counts: counts,
        expanded_org_id: reset.organization.id,
        expanded_extra_id: video.id
      })
    after
      File.rm(path)

      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end
  end)

  then_(
    "both private catalogs contain forty-eight clips and the approved library can add another",
    fn world ->
      assert world.expanded_counts == [48, 48]

      assert Repo.aggregate(
               from(v in Video, where: v.organization_id == ^world.expanded_org_id),
               :count
             ) == 49

      assert Repo.get!(Video, world.expanded_extra_id).mux_asset_id == nil
      world
    end
  )

  when_("a Wanderlust visitor opens private viewer preview on a narrow screen", fn world ->
    import Wallaby.Browser
    import Wallaby.Query
    original = Application.fetch_env(:marquee, :admin_demo)

    path =
      Path.join(
        System.tmp_dir!(),
        "admin-demo-geometry-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))
    host = URI.parse(MarqueeWeb.Endpoint.url()).host
    Application.put_env(:marquee, :admin_demo, enabled: true, host: host, catalog_path: path)

    try do
      {:ok, _} = AdminDemo.configure_host(host)

      session =
        world.session
        |> resize_window(390, 900)
        |> visit("/demo/admin")
        |> click(css("[data-test=admin-demo-start]"))
        |> assert_has(css("[data-test=admin-demo-bar]"))
        |> visit("/?preview=member")
        |> assert_has(css("[data-test=impersonation-banner]"))
        |> assert_has(css("[data-phx-main].phx-connected"))

      Map.put(world, :session, session)
    after
      File.rm(path)

      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end
  end)

  then_("the private demo controls and viewer navigation do not overlap", fn world ->
    Marquee.AdminDemoGeometry.assert_separated(world.session)
    world
  end)

  when_("two Wanderlust visitors edit and reset separate private workspaces", fn world ->
    original = Application.fetch_env(:marquee, :admin_demo)

    path =
      Path.join(
        System.tmp_dir!(),
        "admin-demo-feature-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))

    Application.put_env(:marquee, :admin_demo,
      enabled: true,
      host: "feature-demo.example.test",
      catalog_path: path
    )

    try do
      {:ok, _} = AdminDemo.configure_host("feature-demo.example.test")
      {:ok, first} = AdminDemo.start_session()
      {:ok, second} = AdminDemo.start_session()
      {:ok, %{scope: scope}} = AdminDemo.get_session(second.token)
      video = hd(Content.list_videos(second.organization).results)
      assert {:ok, _} = Content.update_video(scope, video, %{title: "Second visitor keeps this"})
      assert {:ok, replacement} = AdminDemo.reset_session(first.token)
      assert {:error, :revoked} = AdminDemo.get_session(first.token)
      assert {:ok, _} = AdminDemo.get_session(second.token)

      Map.merge(world, %{
        admin_demo_replacement: replacement.organization.id,
        admin_demo_second_video: video.id
      })
    after
      File.rm(path)

      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end
  end)

  then_(
    "the reset visitor has a fresh catalog and the other visitor keeps their edits",
    fn world ->
      assert Repo.get!(Video, world.admin_demo_second_video).title == "Second visitor keeps this"

      titles =
        Repo.all(
          from v in Video,
            where: v.organization_id == ^world.admin_demo_replacement,
            select: v.title
        )

      assert "Travel fixture 1" in titles
      refute "Second visitor keeps this" in titles
      world
    end
  )
end
