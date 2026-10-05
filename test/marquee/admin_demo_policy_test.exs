defmodule Marquee.AdminDemoPolicyTest do
  use Marquee.DataCase, async: false

  import Swoosh.TestAssertions

  alias Marquee.{
    Accounts,
    Admin,
    AdminDemo,
    Billing,
    Branding,
    Catalog,
    Content,
    PlatformBilling,
    Podcasts,
    Storage,
    Streaming,
    TenantDomains,
    Webhooks
  }

  alias Marquee.Accounts.{Membership, Organization, UserNotifier, UserToken}
  alias Marquee.Content.Video
  alias Marquee.Podcasts.AudioProxy
  alias Marquee.Streaming.LiveEventNotifier
  alias Marquee.Viewers.ViewerNotifier

  alias Marquee.Workers.{
    AuditLogExporter,
    MuxAssetCleanup,
    NotifyLiveNowWorker,
    PodcastFeedSync,
    PodcastTokenReconciler,
    RefundPpvTicketsWorker
  }

  @moduletag :tmp_dir
  @host "demo-marquee.example.test"

  setup %{tmp_dir: dir} do
    original = Application.fetch_env(:marquee, :admin_demo)
    path = Path.join(dir, "travel.json")
    manifest = Marquee.AdminDemoFixtures.catalog_manifest()
    File.write!(path, Jason.encode!(manifest))
    Application.put_env(:marquee, :admin_demo, enabled: true, host: @host, catalog_path: path)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end)

    {:ok, host} = AdminDemo.configure_host(@host)
    {:ok, demo} = Oban.Testing.with_testing_mode(:manual, fn -> AdminDemo.start_session() end)
    {:ok, %{scope: scope}} = AdminDemo.get_session(demo.token)
    %{demo: demo, scope: scope, host: host, manifest: manifest, catalog_path: path}
  end

  test "capabilities allow the private editor and reject foreign resources and unsupported effects",
       %{scope: scope} do
    for capability <- [
          :content_edit,
          :catalog_edit,
          :branding_edit,
          :analytics_read,
          :viewer_preview,
          :tour
        ] do
      assert :ok = AdminDemo.authorize(scope, capability)
    end

    foreign = insert(:video)
    assert {:error, :demo_forbidden} = AdminDemo.authorize(scope, :content_edit, foreign)
    assert {:error, :demo_forbidden} = AdminDemo.authorize(scope, :billing)
  end

  test "forged scope and removed database membership cannot authorize", %{scope: scope} do
    assert {:error, :demo_forbidden} =
             AdminDemo.authorize(
               %{scope | admin_demo_session_id: Ecto.UUID.generate()},
               :content_edit
             )

    assert {:error, :demo_forbidden} =
             AdminDemo.authorize(%{scope | user: insert(:user)}, :content_edit)

    Repo.delete!(Repo.get!(Membership, scope.membership.id))
    assert {:error, :demo_forbidden} = AdminDemo.authorize(scope, :content_edit)
  end

  test "expired cached scopes cannot edit even though their structs still look active", %{
    demo: demo,
    scope: scope
  } do
    demo.session
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    video = hd(Content.list_videos(demo.organization).results)
    assert {:error, :demo_expired} = AdminDemo.authorize(scope, :content_edit)
    assert {:error, :demo_expired} = Content.update_video(scope, video, %{title: "Late edit"})
    refute Repo.get!(Video, video.id).title == "Late edit"
  end

  test "ordinary metadata publication and soft removal work without deleting media", %{
    demo: demo,
    scope: scope
  } do
    video = hd(Content.list_videos(demo.organization).results)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, edited} =
               Content.update_video(scope, video, %{title: "My travel edit", published: true})

      assert edited.title == "My travel edit"
      assert edited.published
      assert {:ok, removed} = Content.delete_video(scope, edited)
      assert removed.deleted_at != nil

      refute Repo.exists?(
               from j in Oban.Job, where: j.worker == "Marquee.Workers.MuxAssetCleanup"
             )
    end)
  end

  test "normal content context rejects foreign videos and pasted provider identifiers", %{
    demo: demo,
    scope: scope
  } do
    foreign = insert(:video)
    assert {:error, :demo_forbidden} = Content.update_video(scope, foreign, %{title: "Stolen"})
    assert Repo.get!(Video, foreign.id).title == foreign.title
    video = hd(Content.list_videos(demo.organization).results)

    for attrs <- [
          %{mux_asset_id: "foreign-asset"},
          %{"mux_playback_id" => "foreign-playback"},
          %{mux_upload_id: "foreign-upload"}
        ] do
      assert {:error, :demo_forbidden} = Content.update_video(scope, video, attrs)
    end

    assert Repo.get!(Video, video.id).mux_playback_id == video.mux_playback_id
  end

  test "collections homepage rows and branding remain editable within the sandbox", %{
    demo: demo,
    scope: scope
  } do
    org = demo.organization

    assert {:ok, collection} =
             Content.create_collection(scope, %{
               organization_id: org.id,
               title: "My itinerary",
               slug: "my-itinerary"
             })

    assert collection.organization_id == org.id

    assert {:ok, row} =
             Catalog.create_row(scope, %{
               organization_id: org.id,
               title: "My row",
               source_type: :curated,
               position: 99
             })

    assert {:ok, row} = Catalog.update_row(scope, row, %{visible: true})
    assert row.visible
    theme = Branding.get_theme_by_org(org)
    assert {:ok, theme} = Branding.update_theme(scope, theme, %{background: "#123456"})
    assert theme.background == "#123456"
  end

  test "catalog and branding mutations cannot target another tenant", %{scope: scope} do
    row = insert(:row)
    theme = insert(:theme)
    assert {:error, :demo_forbidden} = Catalog.update_row(scope, row, %{title: "Foreign edit"})

    assert {:error, :demo_forbidden} =
             Branding.update_theme(scope, theme, %{background: "#123456"})

    assert Repo.get!(row.__struct__, row.id).title == row.title
    assert Repo.get!(theme.__struct__, theme.id).background == theme.background
  end

  test "approved extra clip is idempotent and cannot accept arbitrary media", %{
    demo: demo,
    scope: scope,
    manifest: manifest
  } do
    extra = Enum.find(manifest.clips, &(!&1.initial))
    assert {:ok, video} = AdminDemo.add_sample_clip(scope, extra.slug)
    assert video.organization_id == demo.organization.id
    assert video.mux_playback_id == extra.mux_playback_id
    assert video.mux_asset_id == nil
    assert {:ok, repeated} = AdminDemo.add_sample_clip(scope, extra.slug)
    assert repeated.id == video.id

    assert {:error, :demo_forbidden} =
             AdminDemo.add_sample_clip(scope, "https://foreign.example/clip")

    assert {:error, :demo_forbidden} =
             AdminDemo.add_sample_clip(scope, %{mux_asset_id: "arbitrary"})
  end

  test "manifest reload protects newly approved assets before exposing their playback", %{
    scope: scope,
    manifest: manifest,
    catalog_path: path
  } do
    extra = %{
      List.last(manifest.clips)
      | slug: "new-version-clip",
        mux_asset_id: "new-version-protected-asset",
        mux_playback_id: "new-version-playback"
    }

    refute AdminDemo.protected_asset?(extra.mux_asset_id)
    File.write!(path, Jason.encode!(%{manifest | version: 2, clips: manifest.clips ++ [extra]}))
    assert {:ok, video} = AdminDemo.add_sample_clip(scope, extra.slug)
    assert video.mux_playback_id == extra.mux_playback_id
    assert video.mux_asset_id == nil
    assert AdminDemo.protected_asset?(extra.mux_asset_id)
  end

  test "all demo kinds and permanent tombstones deny external effects", %{demo: demo, host: host} do
    real = insert(:organization)
    assert AdminDemo.allow_external_effect?(real)
    assert AdminDemo.allow_external_effect?(real.id)
    refute AdminDemo.allow_external_effect?(demo.organization)
    refute AdminDemo.allow_external_effect?(host.id)
    refute AdminDemo.allow_external_effect?(Ecto.UUID.generate())

    demo.organization
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
    |> Repo.update!()

    refute AdminDemo.allow_external_effect?(demo.organization.id)
  end

  test "provider context families fail before any external call or job", %{
    demo: demo,
    scope: scope
  } do
    org = demo.organization
    show = insert(:podcast_show, organization: org, source_type: "direct_upload")
    plan = insert(:platform_plan, stripe_price_id: "price_demo_forbidden")

    calls = [
      fn -> Content.create_upload_url(scope, %{organization_id: org.id, title: "Upload"}) end,
      fn ->
        Storage.presign_upload(org, "logo", content_type: "image/png", filename: "logo.png")
      end,
      fn -> Podcasts.create_audio_upload_url(scope, show, %{title: "Audio"}) end,
      fn -> Billing.initiate_connect_onboarding(org) end,
      fn -> PlatformBilling.create_org_checkout(org, plan, demo.user) end,
      fn -> Streaming.create_live_event(scope, %{organization_id: org.id, title: "Live"}) end,
      fn ->
        Webhooks.create_endpoint(scope, %{
          organization_id: org.id,
          url: "https://foreign.example/hooks",
          events: ["video.created"]
        })
      end,
      fn -> TenantDomains.request_provisioning(org, source: :backend) end
    ]

    Oban.Testing.with_testing_mode(:manual, fn ->
      before = Repo.aggregate(Oban.Job, :count)
      for call <- calls, do: assert({:error, :demo_forbidden} = call.())
      assert Repo.aggregate(Oban.Job, :count) == before
    end)
  end

  test "synthetic identities cannot receive normal login or email-change capabilities", %{
    demo: demo
  } do
    assert {:error, :demo_forbidden} =
             Accounts.deliver_login_instructions(demo.user, &"https://example.test/#{&1}")

    assert {:error, :demo_forbidden} =
             Accounts.deliver_user_update_email_instructions(
               demo.user,
               demo.user.email,
               &"https://example.test/#{&1}"
             )

    assert Repo.aggregate(UserToken, :count) == 0
    refute_email_sent()
  end

  test "forged provider cleanup jobs are canceled for sandbox and protected asset IDs", %{
    demo: demo,
    manifest: manifest
  } do
    real = insert(:organization)

    for {org_id, asset_id} <- [
          {demo.organization.id, "unprotected-forged"},
          {real.id, hd(manifest.clips).mux_asset_id}
        ] do
      assert {:cancel, :demo_forbidden} =
               MuxAssetCleanup.perform(%Oban.Job{
                 args: %{"organization_id" => org_id, "mux_asset_id" => asset_id}
               })
    end

    future = DateTime.add(demo.session.expires_at, 40 * 86_400)
    assert {:ok, _} = AdminDemo.cleanup_expired(now: future)

    assert {:cancel, :demo_forbidden} =
             MuxAssetCleanup.perform(%Oban.Job{
               args: %{
                 "organization_id" => real.id,
                 "mux_asset_id" => hd(manifest.clips).mux_asset_id
               }
             })
  end

  test "customer inventories and platform totals exclude disposable and service identities", %{
    demo: demo,
    host: host
  } do
    real = insert(:organization)
    real_user = insert(:user)
    insert(:video, organization: real)
    assert Enum.map(Admin.list_organizations().results, & &1.id) == [real.id]
    assert Enum.map(Admin.list_users().results, & &1.id) == [real_user.id]
    assert %{total_organizations: 1, total_users: 1, total_videos: 1} = Admin.platform_stats()
    assert Repo.get!(Organization, demo.organization.id)
    assert Repo.get!(Organization, host.id)
  end

  test "jobs derive sandbox ownership from persisted resources despite foreign organization arguments",
       %{demo: demo} do
    real = insert(:organization)
    show = insert(:podcast_show, organization: demo.organization)
    viewer = insert(:viewer, organization: demo.organization)

    for args <- [%{"show_id" => show.id}, %{"viewer_id" => viewer.id}] do
      job = %Oban.Job{args: Map.put(args, "organization_id", real.id)}
      assert {:cancel, :demo_forbidden} = PodcastTokenReconciler.perform(job)
    end

    assert {:cancel, :demo_forbidden} =
             AuditLogExporter.perform(%Oban.Job{
               args: %{
                 "user_id" => demo.user.id,
                 "organization_id" => real.id,
                 "scope" => "platform"
               },
               attempt: 1
             })
  end

  test "direct notifiers cannot bypass sandbox mail restrictions", %{demo: demo} do
    viewer = insert(:viewer, organization: demo.organization)
    event = insert(:live_event, organization: demo.organization)

    assert {:error, :demo_forbidden} =
             UserNotifier.deliver_login_instructions(
               demo.user,
               "https://example.test/login"
             )

    assert {:error, :demo_forbidden} =
             ViewerNotifier.deliver_magic_link(viewer, "token", demo.organization)

    assert {:error, :demo_forbidden} =
             LiveEventNotifier.deliver_live_now(
               viewer,
               event,
               demo.organization
             )

    refute_email_sent()
  end

  test "podcast proxy rejects sandbox audio before remote fetch or cache writes", %{demo: demo} do
    show = insert(:feed_import_show, organization: demo.organization)

    episode =
      insert(:podcast_episode,
        organization: demo.organization,
        show: show,
        remote_audio_url: "https://media.example.test/private.mp3"
      )

    assert {:error, :demo_forbidden} = AudioProxy.fetch_audio(episode)
  end

  test "feed live-notification and refund jobs reject persisted sandbox resources", %{demo: demo} do
    real = insert(:organization)
    show = insert(:feed_import_show, organization: demo.organization)
    event = insert(:live_event, organization: demo.organization)

    jobs = [
      {PodcastFeedSync, %{"show_id" => show.id}},
      {NotifyLiveNowWorker, %{"live_event_id" => event.id}},
      {RefundPpvTicketsWorker, %{"live_event_id" => event.id}}
    ]

    for {worker, args} <- jobs do
      assert {:cancel, :demo_forbidden} =
               worker.perform(%Oban.Job{args: Map.put(args, "organization_id", real.id)})
    end

    refute_email_sent()
  end

  test "automatic hostname inventory excludes private sandboxes and demo service hosts" do
    pattern = "{slug}-marquee.example.test"

    changes = [
      tenant_host_pattern: pattern,
      tenant_domain_provisioning: [
        enabled: true,
        zone: "example.test",
        account_id: "123",
        api_token: "test-token",
        target_ipv4: "192.0.2.25",
        host_pattern: pattern
      ]
    ]

    originals = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- originals do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    real = insert(:organization)
    snapshot = TenantDomains.migration_snapshot(cutoff: DateTime.add(DateTime.utc_now(), 2))
    assert Enum.map(snapshot.organizations, & &1.organization_id) == [real.id]
  end

  test "collection edits and row attachments validate persisted session and resource ownership",
       %{demo: demo, scope: scope} do
    foreign = insert(:collection)

    assert {:error, :demo_forbidden} =
             Content.update_collection(scope, foreign, %{title: "Foreign edit"})

    row = insert(:row, organization: demo.organization)
    video = insert(:video)
    assert {:error, :demo_forbidden} = Catalog.add_item_to_row(scope, row, video)
    own = insert(:collection, organization: demo.organization)

    demo.session
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:error, :demo_expired} =
             Content.update_collection(scope, own, %{title: "Expired edit"})

    assert Repo.get!(own.__struct__, own.id).title == own.title
  end

  test "forged connected Stripe fields cannot permit sandbox plan creation", %{demo: demo} do
    forged = %{
      demo.organization
      | stripe_connect_account_id: "acct_forged",
        stripe_connect_onboarding_complete: true
    }

    assert {:error, :demo_forbidden} =
             Billing.create_plan_with_stripe(forged, %{
               name: "Forbidden",
               amount: 1000,
               currency: "usd",
               interval: "month"
             })
  end

  test "actual platform overview and health inventory exclude sandbox and service hosts" do
    real = insert(:organization)
    assert Admin.platform_overview().total_orgs == 1
    assert Enum.map(Admin.list_organizations_with_health().results, & &1.id) == [real.id]
  end

  test "theme creation validates demo scope lifetime and tenant ownership", %{
    demo: demo,
    scope: scope
  } do
    Repo.delete!(Branding.get_theme_by_org(demo.organization))
    attrs = %{organization_id: demo.organization.id, background: "#123456"}
    assert {:error, :demo_forbidden} = Branding.create_theme(attrs)
    ordinary = insert(:organization)

    assert {:error, :demo_forbidden} =
             Branding.create_theme(scope, %{attrs | organization_id: ordinary.id})

    assert {:ok, created} = Branding.create_theme(scope, attrs)
    assert created.organization_id == demo.organization.id
    Repo.delete!(created)

    demo.session
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:error, :demo_expired} = Branding.create_theme(scope, attrs)
    assert {:ok, ordinary_theme} = Branding.create_theme(%{attrs | organization_id: ordinary.id})
    assert ordinary_theme.organization_id == ordinary.id
  end
end
