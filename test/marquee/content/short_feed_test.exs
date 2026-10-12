defmodule Marquee.Content.ShortFeedTest do
  # async: false — one test captures exported OpenTelemetry spans and the
  # short-feed cache is invalidated by a separate subscriber process.
  use Marquee.DataCase, async: false

  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.Audit
  alias Marquee.Content

  setup do
    org = insert(:organization, shorts_feed_enabled: true, shorts_feed_access: "public")
    scope = scope_for(org, :editor)
    %{org: org, scope: scope}
  end

  defp scope_for(org, role) do
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: role)
    Scope.for_user(user) |> Scope.with_organization(org, membership)
  end

  # A scope that names one organization while carrying a membership from
  # another. Context role checks must not trust the organization field alone.
  defp mismatched_scope(org) do
    other = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: other, user: user, role: :owner)
    Scope.for_user(user) |> Scope.with_organization(org, membership)
  end

  defp ready_video(org, attrs \\ []) do
    insert(
      :video,
      Keyword.merge(
        [organization: org, mux_status: "ready", duration: 30.0, aspect_ratio: "9:16"],
        attrs
      )
    )
  end

  defp add!(scope, video) do
    {:ok, item} = Content.add_short_feed_video(scope, video)
    item
  end

  defp feed_video_ids(org, opts \\ []) do
    {:ok, page} = Content.list_short_feed(org, opts)
    Enum.map(page.results, & &1.id)
  end

  defp item_video_ids(org) do
    org
    |> Content.list_short_feed_items(per_page: 100)
    |> Map.fetch!(:results)
    |> Enum.map(& &1.video_id)
  end

  defp reload_org(org), do: Repo.get!(Organization, org.id)

  # Counts audit rows written directly by the short-feed context
  # ("short_feed.<action>"). Rows the generic AuditSubscriber derives from
  # event names use dots only and are not counted.
  defp short_feed_audit_count(org) do
    org_id = org.id

    from(l in Audit.Log, where: l.organization_id == ^org_id, select: l.action)
    |> Repo.all()
    |> Enum.count(&String.starts_with?(&1, "short_feed."))
  end

  defp assert_short_feed_event do
    assert_receive {:marquee_event, {name, _payload}, _scope}, 500
    assert name |> Atom.to_string() |> String.starts_with?("short_feed")
  end

  # The cache subscriber invalidates in its own process. PubSub delivers the
  # event to its mailbox before Events.broadcast returns, so a synchronous
  # call guarantees every earlier invalidation has been applied.
  defp settle_cache_subscriber do
    _ = :sys.get_state(Marquee.Content.ShortFeedCacheSubscriber)
    :ok
  end

  defp raw_insert_item(org, video, position) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("short_feed_items", [
      %{
        id: Ecto.UUID.bingenerate(),
        organization_id: Ecto.UUID.dump!(org.id),
        video_id: Ecto.UUID.dump!(video.id),
        position: position,
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  describe "organization defaults" do
    test "a new organization has the feed disabled and subscribers-only access" do
      org = reload_org(insert(:organization))
      assert org.shorts_feed_enabled == false
      assert org.shorts_feed_access == "subscribers_only"
    end
  end

  describe "add_short_feed_video/2" do
    test "appends an eligible video at the end of the feed", %{org: org, scope: scope} do
      v1 = ready_video(org)
      v2 = ready_video(org)

      assert {:ok, first} = Content.add_short_feed_video(scope, v1)
      assert {:ok, second} = Content.add_short_feed_video(scope, v2)

      assert first.organization_id == org.id
      assert first.video_id == v1.id
      assert second.position == first.position + 1
      assert item_video_ids(org) == [v1.id, v2.id]
    end

    test "returns :not_found for another organization's video", %{org: org, scope: scope} do
      foreign = ready_video(insert(:organization))
      assert {:error, :not_found} = Content.add_short_feed_video(scope, foreign)
      assert item_video_ids(org) == []
    end

    test "returns :not_eligible for processing, errored, deleted or unplayable videos", %{
      org: org,
      scope: scope
    } do
      ineligible = [
        ready_video(org, mux_status: "preparing"),
        ready_video(org, mux_status: "waiting"),
        ready_video(org, mux_status: "errored"),
        ready_video(org, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)),
        ready_video(org, mux_playback_id: nil),
        ready_video(org, mux_playback_id: "")
      ]

      for video <- ineligible do
        assert {:error, :not_eligible} = Content.add_short_feed_video(scope, video),
               "expected #{inspect({video.mux_status, video.mux_playback_id, video.deleted_at})} to be ineligible"
      end

      assert item_video_ids(org) == []
    end

    test "returns :already_exists for a video already in the feed", %{org: org, scope: scope} do
      video = ready_video(org)
      add!(scope, video)
      assert {:error, :already_exists} = Content.add_short_feed_video(scope, video)
      assert item_video_ids(org) == [video.id]
    end

    test "returns :plan_limit_reached once the feed holds 200 items", %{org: org, scope: scope} do
      for {video, position} <- Enum.with_index(insert_list(200, :video, organization: org), 1) do
        raw_insert_item(org, video, position)
      end

      extra = ready_video(org)

      assert {:error, :plan_limit_reached, %{limit: 200, current: 200}} =
               Content.add_short_feed_video(scope, extra)
    end

    test "is published as an event and audited", %{org: org, scope: scope} do
      Marquee.Events.subscribe(org.id)
      before = short_feed_audit_count(org)

      add!(scope, ready_video(org))

      assert_short_feed_event()
      assert short_feed_audit_count(org) == before + 1
    end

    test "is wrapped in a marquee.content.add_short_feed_video span", %{org: org, scope: scope} do
      :ok = :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
      on_exit(fn -> :otel_simple_processor.set_exporter(:none) end)

      add!(scope, ready_video(org))

      assert_receive {:span, span} when elem(span, 6) == "marquee.content.add_short_feed_video",
                     1000
    end
  end

  describe "role and tenant enforcement" do
    setup %{org: org, scope: scope} do
      v1 = ready_video(org)
      v2 = ready_video(org)
      i1 = add!(scope, v1)
      i2 = add!(scope, v2)
      %{v1: v1, v2: v2, i1: i1, i2: i2}
    end

    for {label, build} <- [
          {"viewer_support", :viewer_support},
          {"a scope whose membership belongs to another org", :mismatched}
        ] do
      @build build

      test "#{label} is forbidden from every short-feed mutation", ctx do
        scope =
          case @build do
            :viewer_support -> scope_for(ctx.org, :viewer_support)
            :mismatched -> mismatched_scope(ctx.org)
          end

        candidate = ready_video(ctx.org)
        before_audit = short_feed_audit_count(ctx.org)

        assert {:error, :forbidden} = Content.add_short_feed_video(scope, candidate)
        assert {:error, :forbidden} = Content.remove_short_feed_item(scope, ctx.i1)
        assert {:error, :forbidden} = Content.move_short_feed_item(scope, ctx.i2, :up)
        assert {:error, :forbidden} = Content.reorder_short_feed(scope, [ctx.i2.id, ctx.i1.id])

        assert {:error, :forbidden} =
                 Content.update_short_feed_settings(scope, %{
                   enabled: false,
                   access: "subscribers_only"
                 })

        assert item_video_ids(ctx.org) == [ctx.v1.id, ctx.v2.id]
        org = reload_org(ctx.org)
        assert org.shorts_feed_enabled == true
        assert org.shorts_feed_access == "public"
        assert short_feed_audit_count(ctx.org) == before_audit
      end
    end

    test "an editor of another org cannot see or touch this org's items", ctx do
      # Existence is not revealed across tenants.
      other_scope = scope_for(insert(:organization), :owner)

      assert {:error, :not_found} = Content.remove_short_feed_item(other_scope, ctx.i1)
      assert {:error, :not_found} = Content.move_short_feed_item(other_scope, ctx.i2, :up)
      assert item_video_ids(ctx.org) == [ctx.v1.id, ctx.v2.id]
    end

    test "another org cannot reorder this org's items into its own feed", ctx do
      other_scope = scope_for(insert(:organization), :owner)

      assert {:error, :invalid_order} =
               Content.reorder_short_feed(other_scope, [ctx.i2.id, ctx.i1.id])

      assert item_video_ids(ctx.org) == [ctx.v1.id, ctx.v2.id]
    end

    test "owner and admin roles may manage the feed", %{org: org} do
      for role <- [:owner, :admin] do
        scope = scope_for(org, role)
        assert {:ok, _} = Content.add_short_feed_video(scope, ready_video(org))
      end
    end

    test "a super admin may manage the feed", %{org: org} do
      super_admin = insert(:super_admin)
      scope = Scope.for_user(super_admin) |> Scope.with_organization(org, nil)
      assert {:ok, _} = Content.add_short_feed_video(scope, ready_video(org))
    end
  end

  describe "remove_short_feed_item/2" do
    test "removes the item and leaves the video untouched", %{org: org, scope: scope} do
      v1 = ready_video(org)
      v2 = ready_video(org)
      i1 = add!(scope, v1)
      add!(scope, v2)

      assert :ok = Content.remove_short_feed_item(scope, i1)
      assert item_video_ids(org) == [v2.id]
      assert {:error, :not_found} = Content.get_short_feed_item(org, i1.id)
      assert Content.get_video!(org, v1.id).deleted_at == nil
    end

    test "returns :not_found when the item was already removed", %{org: org, scope: scope} do
      item = add!(scope, ready_video(org))
      :ok = Content.remove_short_feed_item(scope, item)
      assert {:error, :not_found} = Content.remove_short_feed_item(scope, item)
    end

    test "is published as an event and audited", %{org: org, scope: scope} do
      item = add!(scope, ready_video(org))
      Marquee.Events.subscribe(org.id)
      before = short_feed_audit_count(org)

      :ok = Content.remove_short_feed_item(scope, item)

      assert_short_feed_event()
      assert short_feed_audit_count(org) == before + 1
    end
  end

  describe "move_short_feed_item/3" do
    setup %{org: org, scope: scope} do
      [v1, v2, v3] = for _ <- 1..3, do: ready_video(org)
      [i1, i2, i3] = Enum.map([v1, v2, v3], &add!(scope, &1))
      %{v1: v1, v2: v2, v3: v3, i1: i1, i2: i2, i3: i3}
    end

    test "moves an item up and down", ctx do
      assert :ok = Content.move_short_feed_item(ctx.scope, ctx.i2, :up)
      assert item_video_ids(ctx.org) == [ctx.v2.id, ctx.v1.id, ctx.v3.id]

      {:ok, i1} = Content.get_short_feed_item(ctx.org, ctx.i1.id)
      assert :ok = Content.move_short_feed_item(ctx.scope, i1, :down)
      assert item_video_ids(ctx.org) == [ctx.v2.id, ctx.v3.id, ctx.v1.id]
    end

    test "is a no-op at the boundaries", ctx do
      assert :ok = Content.move_short_feed_item(ctx.scope, ctx.i1, :up)
      assert :ok = Content.move_short_feed_item(ctx.scope, ctx.i3, :down)
      assert item_video_ids(ctx.org) == [ctx.v1.id, ctx.v2.id, ctx.v3.id]
    end

    test "is published as an event and audited", ctx do
      Marquee.Events.subscribe(ctx.org.id)
      before = short_feed_audit_count(ctx.org)

      :ok = Content.move_short_feed_item(ctx.scope, ctx.i3, :up)

      assert_short_feed_event()
      assert short_feed_audit_count(ctx.org) == before + 1
    end
  end

  describe "reorder_short_feed/2" do
    setup %{org: org, scope: scope} do
      [v1, v2, v3] = for _ <- 1..3, do: ready_video(org)
      [i1, i2, i3] = Enum.map([v1, v2, v3], &add!(scope, &1))
      %{v1: v1, v2: v2, v3: v3, i1: i1, i2: i2, i3: i3}
    end

    test "applies the given order", ctx do
      assert :ok = Content.reorder_short_feed(ctx.scope, [ctx.i3.id, ctx.i1.id, ctx.i2.id])
      assert item_video_ids(ctx.org) == [ctx.v3.id, ctx.v1.id, ctx.v2.id]
    end

    test "rejects a set that is not exactly the org's items", ctx do
      foreign_scope = scope_for(insert(:organization), :editor)
      foreign_item = add!(foreign_scope, ready_video(foreign_scope.organization))

      for ids <- [
            [ctx.i1.id, ctx.i2.id],
            [ctx.i1.id, ctx.i2.id, ctx.i3.id, foreign_item.id],
            [ctx.i1.id, ctx.i2.id, foreign_item.id],
            [ctx.i1.id, ctx.i1.id, ctx.i2.id, ctx.i3.id],
            [ctx.i1.id, ctx.i2.id, Ecto.UUID.generate()],
            []
          ] do
        assert {:error, :invalid_order} = Content.reorder_short_feed(ctx.scope, ids),
               "expected #{inspect(ids)} to be rejected"
      end

      assert item_video_ids(ctx.org) == [ctx.v1.id, ctx.v2.id, ctx.v3.id]
    end

    test "is published as an event and audited", ctx do
      Marquee.Events.subscribe(ctx.org.id)
      before = short_feed_audit_count(ctx.org)

      :ok = Content.reorder_short_feed(ctx.scope, [ctx.i2.id, ctx.i3.id, ctx.i1.id])

      assert_short_feed_event()
      assert short_feed_audit_count(ctx.org) == before + 1
    end
  end

  describe "update_short_feed_settings/2" do
    test "updates the enabled flag and access level", %{org: org, scope: scope} do
      assert {:ok, %Organization{} = updated} =
               Content.update_short_feed_settings(scope, %{
                 enabled: false,
                 access: "free_with_account"
               })

      assert updated.shorts_feed_enabled == false
      assert updated.shorts_feed_access == "free_with_account"

      reloaded = reload_org(org)
      assert reloaded.shorts_feed_enabled == false
      assert reloaded.shorts_feed_access == "free_with_account"
    end

    test "accepts each supported access level", %{scope: scope} do
      for level <- ["public", "free_with_account", "subscribers_only"] do
        assert {:ok, %{shorts_feed_access: ^level}} =
                 Content.update_short_feed_settings(scope, %{enabled: true, access: level})
      end
    end

    test "rejects an unknown access level", %{org: org, scope: scope} do
      assert {:error, :validation, %Ecto.Changeset{} = changeset} =
               Content.update_short_feed_settings(scope, %{enabled: true, access: "everyone"})

      assert %{shorts_feed_access: [_ | _]} = errors_on(changeset)
      assert reload_org(org).shorts_feed_access == "public"
    end

    test "does not change unrelated organization fields", %{org: org, scope: scope} do
      {:ok, _} =
        Content.update_short_feed_settings(scope, %{
          enabled: true,
          access: "subscribers_only",
          name: "Hijacked",
          slug: "hijacked"
        })

      reloaded = reload_org(org)
      assert reloaded.name == org.name
      assert reloaded.slug == org.slug
    end

    test "is published as an event and audited", %{org: org, scope: scope} do
      Marquee.Events.subscribe(org.id)
      before = short_feed_audit_count(org)

      {:ok, _} = Content.update_short_feed_settings(scope, %{enabled: true, access: "public"})

      assert_short_feed_event()
      assert short_feed_audit_count(org) == before + 1
    end
  end

  describe "list_short_feed/2" do
    test "returns eligible videos in feed order with pagination metadata", %{
      org: org,
      scope: scope
    } do
      [v1, v2, v3] = for _ <- 1..3, do: ready_video(org)
      Enum.each([v2, v3, v1], &add!(scope, &1))

      assert {:ok, page} = Content.list_short_feed(org, page: 1, per_page: 2)
      assert Enum.map(page.results, & &1.id) == [v2.id, v3.id]
      assert page.page == 1
      assert page.per_page == 2
      assert page.total == 3
      assert page.total_pages == 2

      assert {:ok, page2} = Content.list_short_feed(org, page: 2, per_page: 2)
      assert Enum.map(page2.results, & &1.id) == [v1.id]
    end

    test "defaults to 8 per page", %{org: org, scope: scope} do
      for _ <- 1..10, do: add!(scope, ready_video(org))

      assert {:ok, page} = Content.list_short_feed(org)
      assert page.per_page == 8
      assert length(page.results) == 8
      assert page.total == 10
    end

    test "caps per_page at 100", %{org: org, scope: scope} do
      add!(scope, ready_video(org))
      assert {:ok, page} = Content.list_short_feed(org, per_page: 500)
      assert page.per_page == 100
    end

    test "returns :feed_disabled when the organization has the feed off" do
      org = insert(:organization, shorts_feed_enabled: false)
      off_scope = scope_for(org, :editor)
      add!(off_scope, ready_video(org))

      assert {:error, :feed_disabled} = Content.list_short_feed(org)
    end

    test "only includes items whose video is still eligible", %{org: org, scope: scope} do
      [v1, v2, v3] = for _ <- 1..3, do: ready_video(org)
      Enum.each([v1, v2, v3], &add!(scope, &1))

      {:ok, _} = Content.mark_video_errored(v1.mux_asset_id, %{})
      {:ok, _} = Content.delete_video(scope, v2)

      assert feed_video_ids(org) == [v3.id]
      assert {:ok, %{total: 1}} = Content.list_short_feed(org)
    end

    test "only_video_ids restricts results to the given videos", %{org: org, scope: scope} do
      [v1, v2, v3] = for _ <- 1..3, do: ready_video(org)
      Enum.each([v1, v2, v3], &add!(scope, &1))

      assert feed_video_ids(org, only_video_ids: [v3.id, v1.id]) == [v1.id, v3.id]
      assert {:ok, %{total: 2}} = Content.list_short_feed(org, only_video_ids: [v3.id, v1.id])
    end

    test "never returns another organization's feed", %{org: org, scope: scope} do
      mine = ready_video(org)
      add!(scope, mine)

      other_org = insert(:organization, shorts_feed_enabled: true, shorts_feed_access: "public")
      other_scope = scope_for(other_org, :editor)
      theirs = ready_video(other_org)
      add!(other_scope, theirs)

      assert feed_video_ids(org) == [mine.id]
      assert feed_video_ids(other_org) == [theirs.id]
      assert feed_video_ids(org, only_video_ids: [theirs.id]) == []
    end
  end

  describe "short feed caching" do
    test "serves the org feed from cache until a short-feed mutation", %{org: org} do
      # Rows are written directly so no invalidation event is in flight.
      v1 = ready_video(org)
      raw_insert_item(org, v1, 1)
      assert feed_video_ids(org) == [v1.id]

      # A row written behind the context's back is invisible while cached...
      sneaky = ready_video(org)
      raw_insert_item(org, sneaky, 50)
      assert feed_video_ids(org) == [v1.id]

      # ...but only_video_ids queries bypass the org-wide cache.
      assert feed_video_ids(org, only_video_ids: [sneaky.id]) == [sneaky.id]
    end

    test "is invalidated after add", %{org: org, scope: scope} do
      v1 = ready_video(org)
      add!(scope, v1)
      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id]

      v2 = ready_video(org)
      add!(scope, v2)

      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id, v2.id]
    end

    test "is invalidated after remove", %{org: org, scope: scope} do
      v1 = ready_video(org)
      v2 = ready_video(org)
      i1 = add!(scope, v1)
      add!(scope, v2)
      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id, v2.id]

      :ok = Content.remove_short_feed_item(scope, i1)

      settle_cache_subscriber()
      assert feed_video_ids(org) == [v2.id]
    end

    test "is invalidated after reorder", %{org: org, scope: scope} do
      v1 = ready_video(org)
      v2 = ready_video(org)
      i1 = add!(scope, v1)
      i2 = add!(scope, v2)
      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id, v2.id]

      :ok = Content.reorder_short_feed(scope, [i2.id, i1.id])

      settle_cache_subscriber()
      assert feed_video_ids(org) == [v2.id, v1.id]
    end

    test "is invalidated after move", %{org: org, scope: scope} do
      v1 = ready_video(org)
      v2 = ready_video(org)
      add!(scope, v1)
      i2 = add!(scope, v2)
      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id, v2.id]

      :ok = Content.move_short_feed_item(scope, i2, :up)

      settle_cache_subscriber()
      assert feed_video_ids(org) == [v2.id, v1.id]
    end

    test "is invalidated when a feed video becomes errored", %{org: org, scope: scope} do
      v1 = ready_video(org)
      v2 = ready_video(org)
      add!(scope, v1)
      add!(scope, v2)
      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id, v2.id]

      {:ok, _} = Content.mark_video_errored(v1.mux_asset_id, %{})

      settle_cache_subscriber()
      assert feed_video_ids(org) == [v2.id]
    end

    test "is invalidated when a feed video becomes ready", %{org: org, scope: scope} do
      v1 = ready_video(org)
      add!(scope, v1)

      pending =
        ready_video(org,
          mux_status: "preparing",
          mux_playback_id: nil,
          mux_asset_id: "asset_pending_short"
        )

      raw_insert_item(org, pending, 99)
      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id]

      {:ok, _} =
        Content.mark_video_ready("asset_pending_short", %{
          duration: 12.0,
          max_resolution: "HD",
          playback_id: "pb_now_ready",
          aspect_ratio: "9:16"
        })

      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id, pending.id]
    end

    test "is invalidated when a feed video is deleted", %{org: org, scope: scope} do
      v1 = ready_video(org)
      v2 = ready_video(org)
      add!(scope, v1)
      add!(scope, v2)
      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id, v2.id]

      {:ok, _} = Content.delete_video(scope, v2)

      settle_cache_subscriber()
      assert feed_video_ids(org) == [v1.id]
    end

    test "is invalidated when a feed video is updated", %{org: org, scope: scope} do
      v1 = ready_video(org, title: "Before")
      add!(scope, v1)
      settle_cache_subscriber()
      {:ok, page} = Content.list_short_feed(org)
      assert Enum.map(page.results, & &1.title) == ["Before"]

      {:ok, _} = Content.update_video(scope, v1, %{title: "After"})

      settle_cache_subscriber()
      {:ok, page} = Content.list_short_feed(org)
      assert Enum.map(page.results, & &1.title) == ["After"]
    end

    test "cached feeds are namespaced per organization", %{org: org, scope: scope} do
      mine = ready_video(org)
      add!(scope, mine)
      assert feed_video_ids(org) == [mine.id]

      other_org = insert(:organization, shorts_feed_enabled: true, shorts_feed_access: "public")
      assert feed_video_ids(other_org) == []
    end
  end

  describe "list_short_feed_items/2" do
    test "includes unavailable items in position order with their videos", %{
      org: org,
      scope: scope
    } do
      v1 = ready_video(org, title: "Good")
      v2 = ready_video(org, title: "Broken")
      add!(scope, v1)
      add!(scope, v2)
      {:ok, _} = Content.mark_video_errored(v2.mux_asset_id, %{})

      page = Content.list_short_feed_items(org)
      assert %{results: [first, second], total: 2, page: 1} = page
      assert first.video.title == "Good"
      assert second.video.title == "Broken"
      assert second.video.mux_status == "errored"
    end

    test "is scoped to the organization", %{org: org, scope: scope} do
      add!(scope, ready_video(org))
      other_org = insert(:organization)
      assert %{results: [], total: 0} = Content.list_short_feed_items(other_org)
    end
  end

  describe "admin list per_page cap" do
    test "list_short_feed_items and list_short_feed_eligible_videos cap per_page at 100", %{
      org: org,
      scope: scope
    } do
      add!(scope, ready_video(org))
      ready_video(org)

      assert %{per_page: 100} = Content.list_short_feed_items(org, per_page: 500)
      assert %{per_page: 100} = Content.list_short_feed_eligible_videos(org, per_page: 500)
    end
  end

  describe "get_short_feed_item/2" do
    test "returns the org's item and hides other orgs' items", %{org: org, scope: scope} do
      item = add!(scope, ready_video(org))

      assert {:ok, found} = Content.get_short_feed_item(org, item.id)
      assert found.id == item.id
      assert {:error, :not_found} = Content.get_short_feed_item(insert(:organization), item.id)
      assert {:error, :not_found} = Content.get_short_feed_item(org, Ecto.UUID.generate())
    end
  end

  describe "list_short_feed_eligible_videos/2" do
    test "offers only eligible, same-org videos not already in the feed", %{
      org: org,
      scope: scope
    } do
      eligible = ready_video(org, title: "Eligible Clip")
      in_feed = ready_video(org, title: "Already In")
      add!(scope, in_feed)

      _processing = ready_video(org, mux_status: "preparing")
      _errored = ready_video(org, mux_status: "errored")
      _deleted = ready_video(org, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      _no_playback = ready_video(org, mux_playback_id: nil)
      _foreign = ready_video(insert(:organization))

      page = Content.list_short_feed_eligible_videos(org)
      assert Enum.map(page.results, & &1.id) == [eligible.id]
      assert page.total == 1
    end

    test "filters by search term and paginates", %{org: org} do
      alpha = ready_video(org, title: "Alpha Dance")
      _beta = ready_video(org, title: "Beta Cooking")

      assert %{results: [found]} =
               Content.list_short_feed_eligible_videos(org, search: "alpha")

      assert found.id == alpha.id

      assert %{per_page: 1, total: 2, total_pages: 2, results: [_]} =
               Content.list_short_feed_eligible_videos(org, page: 1, per_page: 1)
    end
  end
end
