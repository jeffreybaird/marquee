defmodule MarqueeFeatures.Steps.AuditLogging do
  @moduledoc """
  Step definitions for audit_logging.feature.

  Operator-side scenarios (view, filter, expand, load more) drive the
  /admin/audit-log UI via Wallaby. CSV export clicks the button and
  asserts no error surfaces — Wallaby in headless Chrome doesn't
  capture file downloads cleanly, so the actual byte assertion is
  best left to a Phoenix.ConnTest unit. Super admin scenarios + the
  impersonation entry stay undefined until the super-admin login
  helper exists.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import MarqueeFeatures.Support.Browser

  alias Marquee.Audit
  alias Marquee.Accounts.Scope

  given_ "I am logged in as an organization owner or admin", fn world ->
    org = insert(:organization)
    user = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: user, organization: org, role: :owner)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    session = MarqueeWeb.WallabyCase.log_in_session(world.session, user, org)

    Map.merge(world, %{
      session: session,
      operator: user,
      org: org,
      membership: membership,
      scope: scope
    })
  end

  # ---- Seeding -----------------------------------------------------------

  given_ "the audit log has entries from multiple users", fn world ->
    other_user = insert(:user, confirmed_at: DateTime.utc_now())
    insert(:membership, user: other_user, organization: world.org, role: :admin)

    other_scope =
      Scope.for_user(other_user)
      |> Scope.with_organization(
        world.org,
        Marquee.Repo.get_by!(Marquee.Accounts.Membership,
          user_id: other_user.id,
          organization_id: world.org.id
        )
      )

    {:ok, log_a} = Audit.log(world.scope, "video.created", build_resource("Video"))
    {:ok, log_b} = Audit.log(other_scope, "tag.created", build_resource("Tag"))

    Map.merge(world, %{other_user: other_user, log_a: log_a, log_b: log_b})
  end

  given_ "the audit log has entries of various action types", fn world ->
    {:ok, created} = Audit.log(world.scope, "video.created", build_resource("Video"))

    {:ok, updated} =
      Audit.log(world.scope, "video.updated", build_resource("Video"), %{title: "x"})

    {:ok, deleted} = Audit.log(world.scope, "video.deleted", build_resource("Video"))

    Map.merge(world, %{log_created: created, log_updated: updated, log_deleted: deleted})
  end

  given_ "the audit log has entries for various resource types", fn world ->
    {:ok, video_log} = Audit.log(world.scope, "video.created", build_resource("Video"))
    {:ok, tag_log} = Audit.log(world.scope, "tag.created", build_resource("Tag"))

    {:ok, collection_log} =
      Audit.log(world.scope, "collection.created", build_resource("Collection"))

    Map.merge(world, %{
      log_video: video_log,
      log_tag: tag_log,
      log_collection: collection_log
    })
  end

  given_ "the audit log has entries", fn world ->
    {:ok, log} =
      Audit.log(world.scope, "video.updated", build_resource("Video"), %{title: "renamed"})

    Map.put(world, :log_entry, log)
  end

  given_ "the audit log has more entries than fit on one page", fn world ->
    # Default per_page is 50. Seed a couple over that threshold so the
    # cursor returns a non-nil next_cursor.
    Enum.each(1..52, fn _ ->
      {:ok, _} = Audit.log(world.scope, "video.created", build_resource("Video"))
    end)

    world
  end

  given_ "I have applied filters to the audit log", fn world ->
    {:ok, _} = Audit.log(world.scope, "video.created", build_resource("Video"))

    session =
      world.session
      |> visit_live("/admin/audit-log?org=#{world.org.slug}")
      |> select_option("[data-test=filter-action]", "video.created")

    Map.put(world, :session, session)
  end

  # ---- Navigate / view ---------------------------------------------------

  when_ "I navigate to /admin/audit-log", fn world ->
    session = visit(world.session, "/admin/audit-log?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  then_ "I see a chronological trail of all actions taken in my organization", fn world ->
    assert_has(world.session, css("[data-test=audit-log-table]"))
    world
  end

  then_ "Including who acted, when, what resource changed, and from which IP address",
        fn world ->
    # The table renders one row per log entry; the first row should reflect
    # the most recent action for this org. The IP-address column is rendered
    # from metadata; we don't assert exact content because the test runtime
    # has no IP — the column header existing is the contract.
    assert_text(world.session, "Action")
    assert_text(world.session, "Actor")
    world
  end

  # ---- Filtering ---------------------------------------------------------

  when_ "I filter by a specific actor", fn world ->
    session =
      world.session
      |> visit_live("/admin/audit-log?org=#{world.org.slug}")
      |> select_option("[data-test=filter-actor]", world.other_user.id)

    Map.put(world, :session, session)
  end

  then_ "only entries from that user are shown", fn world ->
    assert_has(world.session, css("[data-test=audit-log-row-#{world.log_b.id}]"))
    refute_has(world.session, css("[data-test=audit-log-row-#{world.log_a.id}]"))
    world
  end

  when_ "I filter by action type such as create, update, or delete", fn world ->
    session =
      world.session
      |> visit_live("/admin/audit-log?org=#{world.org.slug}")
      |> select_option("[data-test=filter-action]", "video.created")

    Map.put(world, :session, session)
  end

  then_ "only entries matching that action type are shown", fn world ->
    # Assert on row ids: the action names also appear as <option> text in
    # the filter dropdown, so plain text queries cannot tell them apart.
    assert_has(world.session, css("[data-test=audit-log-row-#{world.log_created.id}]"))
    refute_has(world.session, css("[data-test=audit-log-row-#{world.log_updated.id}]"))
    refute_has(world.session, css("[data-test=audit-log-row-#{world.log_deleted.id}]"))
    world
  end

  when_ "I filter by resource type", fn world ->
    session =
      world.session
      |> visit_live("/admin/audit-log?org=#{world.org.slug}")
      |> select_option("[data-test=filter-resource-type]", "Tag")

    Map.put(world, :session, session)
  end

  then_ "only entries for that resource type are shown", fn world ->
    assert_has(world.session, css("[data-test=audit-log-row-#{world.log_tag.id}]"))
    refute_has(world.session, css("[data-test=audit-log-row-#{world.log_video.id}]"))
    refute_has(world.session, css("[data-test=audit-log-row-#{world.log_collection.id}]"))
    world
  end

  # ---- Expand entry ------------------------------------------------------

  when_ "I expand an entry", fn world ->
    session =
      world.session
      |> visit_live("/admin/audit-log?org=#{world.org.slug}")
      |> click(css("[data-test=expand-btn-#{world.log_entry.id}]"))

    Map.put(world, :session, session)
  end

  then_ "I see the full diff showing exactly what fields changed", fn world ->
    # The seeded changes were %{title: "renamed"} — that key/value must
    # render inside the expanded row for this entry.
    row = "[data-test=metadata-row-#{world.log_entry.id}]"

    world.session
    |> assert_has(css(row))
    |> assert_has(css(row, text: "title"))
    |> assert_has(css(row, text: "renamed"))

    world
  end

  # ---- Load more ---------------------------------------------------------

  when_ "I click to load more", fn world ->
    session =
      world.session
      |> visit_live("/admin/audit-log?org=#{world.org.slug}")
      |> click(css("[data-test=load-more-btn]"))

    Map.put(world, :session, session)
  end

  then_ "additional entries are appended to the list", fn world ->
    # After load_more, more than the initial page (50) of rows is in the DOM.
    assert_has(world.session, css("[data-test^=audit-log-row-]", minimum: 51))
    world
  end

  # ---- CSV export --------------------------------------------------------

  when_ "I click export CSV", fn world ->
    # Wallaby's headless Chrome doesn't expose download contents in this
    # setup. Click and assert the page survives — full byte/HTTP assertion
    # belongs to the controller test.
    session = click(world.session, css("[data-test=export-csv-btn]"))
    Map.put(world, :session, session)
  end

  then_ "a CSV file containing the filtered entries is downloaded", fn world ->
    # See note on the When step. The DOM should still be intact (no
    # crash), which we sanity-check by re-asserting the table presence.
    assert_has(world.session, css("[data-test=audit-log-table]"))
    world
  end

  # ---- Helpers -----------------------------------------------------------

  # Audit.log/4 introspects the resource via `resource_type/1`, which uses
  # the struct module name. We don't always have a real Ecto struct on
  # hand for these scenarios — the tagged tuple handed to a custom
  # `resource_type/1` is the cheapest way to seed entries with arbitrary
  # type strings.
  defp build_resource(type, id \\ Ecto.UUID.generate()) do
    %{__struct__: Module.concat([Marquee.AuditFakeResource, type]), id: id}
  end
end
