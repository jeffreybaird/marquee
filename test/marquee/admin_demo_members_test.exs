defmodule Marquee.AdminDemoMembersTest do
  use Marquee.DataCase, async: false
  import Swoosh.TestAssertions
  alias Marquee.{AdminDemo, AdminDemoFixtures, Podcasts, Viewers}
  alias Marquee.Engagement.{Progress, WatchlistItem}
  alias Marquee.Podcasts.{Episode, FeedToken, Show}
  alias Marquee.Viewers.{Viewer, ViewerToken}

  @moduletag :tmp_dir
  setup %{tmp_dir: dir} do
    path = Path.join(dir, "catalog.json")
    File.write!(path, Jason.encode!(AdminDemoFixtures.catalog_manifest()))
    original = Application.fetch_env(:marquee, :admin_demo)

    Application.put_env(:marquee, :admin_demo,
      enabled: true,
      host: "demo.example.test",
      catalog_path: path
    )

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end)

    {:ok, _} = AdminDemo.configure_host("demo.example.test")
    {:ok, demo} = AdminDemo.start_session()
    {:ok, %{scope: scope}} = AdminDemo.get_session(demo.token)
    %{demo: demo, scope: scope}
  end

  test "each sandbox seeds six varied local sample viewers without credentials or provider records",
       %{demo: demo} do
    viewers = Viewers.list_viewers(demo.organization).results
    assert length(viewers) == 6
    assert viewers |> Enum.map(& &1.status) |> Enum.uniq() |> length() >= 3
    assert viewers |> Enum.map(& &1.subscription_status) |> Enum.uniq() |> length() >= 3

    for viewer <- viewers do
      assert String.ends_with?(viewer.email, ".invalid")
      assert viewer.display_name != nil
      assert viewer.hashed_password == nil
      assert viewer.stripe_customer_id == nil
      assert viewer.metadata["admin_demo_sample"] == true
    end

    assert Repo.aggregate(ViewerToken, :count) == 0

    assert Repo.exists?(
             from p in Progress,
               where: p.organization_id == ^demo.organization.id and not is_nil(p.viewer_id)
           )

    assert Repo.exists?(
             from w in WatchlistItem,
               where: w.organization_id == ^demo.organization.id and not is_nil(w.viewer_id)
           )

    refute_email_sent()
  end

  test "forged resource organization fields cannot bypass persisted sandbox authorization", %{
    demo: demo
  } do
    ordinary = insert(:organization)
    viewer = hd(Viewers.list_viewers(demo.organization).results)
    show = Repo.one!(from s in Show, where: s.organization_id == ^demo.organization.id, limit: 1)

    assert {:error, :demo_forbidden} =
             Viewers.suspend_viewer(nil, %{viewer | organization_id: ordinary.id})

    assert Repo.get!(Viewer, viewer.id).status == viewer.status

    assert {:error, :demo_forbidden} =
             Podcasts.update_show(nil, %{show | organization_id: ordinary.id}, %{
               title: "Forged edit"
             })

    assert Repo.get!(Show, show.id).title == show.title
  end

  test "two local podcast shows are seeded without episodes or remote feeds", %{demo: demo} do
    shows = Repo.all(from s in Show, where: s.organization_id == ^demo.organization.id)
    assert length(shows) == 2

    for show <- shows do
      assert show.source_type == "direct_upload"
      assert show.remote_feed_url == nil
      assert show.audio_only_plan_id == nil
    end

    refute Repo.exists?(from e in Episode, where: e.organization_id == ^demo.organization.id)
    refute Repo.exists?(from t in FeedToken, where: t.organization_id == ^demo.organization.id)
  end

  test "local member status and access changes work but foreign and unscoped writes are denied",
       %{demo: demo, scope: scope} do
    viewer = insert(:viewer, organization: demo.organization)
    assert {:ok, suspended} = Viewers.suspend_viewer(scope, viewer)
    assert suspended.status == :suspended
    assert {:ok, active} = Viewers.reactivate_viewer(scope, suspended)
    assert active.status == :active
    assert {:ok, granted} = Viewers.grant_access(scope, active)
    assert granted.subscription_status == "active"
    assert {:ok, revoked} = Viewers.revoke_access(scope, granted)
    assert revoked.subscription_status == "none"
    foreign = insert(:viewer)

    for action <- [&Viewers.suspend_viewer/2, &Viewers.grant_access/2, &Viewers.revoke_access/2] do
      assert {:error, :demo_forbidden} = action.(scope, foreign)
      assert {:error, :demo_forbidden} = action.(nil, viewer)
    end

    assert Repo.get!(Viewer, foreign.id).status == foreign.status
    refute_email_sent()
  end

  test "persisted expiry invalidates cached member scope before local mutation", %{
    demo: demo,
    scope: scope
  } do
    viewer = insert(:viewer, organization: demo.organization)

    Repo.update!(
      Ecto.Changeset.change(demo.session, expires_at: DateTime.add(DateTime.utc_now(), -1))
    )

    assert {:error, :demo_expired} = Viewers.ban_viewer(scope, viewer)
    assert Repo.get!(Viewer, viewer.id).status == :active
  end

  test "sample viewers cannot escape through normal authentication APIs", %{demo: demo} do
    viewer = insert(:viewer, organization: demo.organization)
    assert {:error, :demo_forbidden} = Viewers.generate_viewer_session_token(viewer)

    assert {:error, :demo_forbidden} =
             Viewers.deliver_viewer_magic_link(demo.organization, viewer.email)

    assert {:error, :demo_forbidden} =
             Viewers.register_viewer(demo.organization, %{
               email: "new@example.invalid",
               display_name: "Forged signup"
             })

    assert Repo.aggregate(ViewerToken, :count) == 0
    refute_email_sent()
    {raw, persisted} = ViewerToken.build_session_token(viewer)
    Repo.insert!(persisted)
    assert Viewers.get_viewer_by_session_token(raw) == nil
    {magic, persisted} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(persisted)
    assert {:error, :invalid_token} = Viewers.verify_viewer_magic_link(magic)
    ordinary = insert(:viewer)
    token = Viewers.generate_viewer_session_token(ordinary)
    assert is_binary(token)
    assert Viewers.get_viewer_by_session_token(token).id == ordinary.id
  end

  test "podcast metadata publication and removal work locally with scoped authorization", %{
    demo: demo,
    scope: scope
  } do
    attrs = %{
      title: "My local show",
      slug: "my-local-show",
      source_type: "direct_upload",
      access_mode: "any_active"
    }

    assert {:ok, show} = Podcasts.create_show(scope, attrs)
    assert show.organization_id == demo.organization.id

    assert {:ok, updated} =
             Podcasts.update_show(scope, show, %{title: "Edited show", published: true})

    assert updated.title == "Edited show"
    assert updated.published
    assert {:ok, deleted} = Podcasts.soft_delete_show(scope, updated)
    assert deleted.deleted_at != nil
    foreign = insert(:podcast_show)
    assert {:error, :demo_forbidden} = Podcasts.update_show(scope, foreign, %{title: "Foreign"})
    assert {:error, :demo_forbidden} = Podcasts.soft_delete_show(scope, foreign)
  end

  test "podcast operations reject remote sources provider identifiers foreign plans and expired scopes",
       %{demo: demo, scope: scope} do
    show = insert(:podcast_show, organization: demo.organization)
    plan = insert(:plan)

    for attrs <- [
          %{remote_feed_url: "https://example.test/feed.xml"},
          %{source_type: "feed_import"},
          %{mux_asset_id: "pasted"},
          %{tier_plan_ids: [plan.id]},
          %{audio_only_plan_id: plan.id}
        ] do
      assert {:error, :demo_forbidden} = Podcasts.update_show(scope, show, attrs)
    end

    assert {:error, :demo_forbidden} =
             Podcasts.create_show(scope, %{
               title: "Remote",
               slug: "remote",
               source_type: "feed_import",
               remote_feed_url: "https://example.test/feed.xml"
             })

    Repo.update!(
      Ecto.Changeset.change(demo.session, expires_at: DateTime.add(DateTime.utc_now(), -1))
    )

    assert {:error, :demo_expired} = Podcasts.update_show(scope, show, %{title: "Expired"})
  end

  test "podcast upload and feed capabilities remain disabled", %{demo: demo, scope: scope} do
    show = insert(:podcast_show, organization: demo.organization)
    viewer = insert(:viewer, organization: demo.organization)

    assert {:error, :demo_forbidden} =
             Podcasts.create_audio_upload_url(scope, show, %{title: "Upload"})

    assert {:error, :demo_forbidden} = Podcasts.issue_feed_token(show, viewer)
    assert {:error, :demo_forbidden} = Podcasts.regenerate_feed_token(show, viewer)
    assert Repo.aggregate(FeedToken, :count) == 0
  end

  test "reset isolates fresh members and twenty-four-hour cleanup purges all sample data", %{
    demo: demo
  } do
    {:ok, replacement} = AdminDemo.reset_session(demo.token)
    assert length(Viewers.list_viewers(replacement.organization).results) == 6
    old_ids = Viewers.list_viewers(demo.organization).results |> Enum.map(& &1.id)
    new_ids = Viewers.list_viewers(replacement.organization).results |> Enum.map(& &1.id)
    assert MapSet.disjoint?(MapSet.new(old_ids), MapSet.new(new_ids))
    ordinary = insert(:viewer)
    ordinary_show = insert(:podcast_show)
    now = DateTime.add(DateTime.utc_now(), 25 * 3600)
    assert {:ok, _} = AdminDemo.cleanup_expired(now: now)

    for schema <- [Viewer, Progress, WatchlistItem, Show] do
      refute Repo.exists?(from r in schema, where: r.organization_id == ^demo.organization.id)
    end

    assert Repo.get!(Viewer, ordinary.id)
    assert Repo.get!(Show, ordinary_show.id)
  end
end
