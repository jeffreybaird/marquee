defmodule MarqueeFeatures.Steps.AuditLogging do
  @moduledoc """
  Step definitions for audit_logging.feature.

  Operator-side scenarios (view, filter, expand, load more) drive the
  /admin/audit-log UI via Wallaby. CSV export clicks the button; the
  inline export job's upload is captured from the storage mock so the
  CSV bytes can be checked against the active filter. The impersonation scenario
  drives a second browser session as a super admin. Super admin
  scenarios drive /super/audit-log and /super/users.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions
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
    {:ok, _} = Audit.log(world.scope, "tag.created", build_resource("Tag"))

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

  then_ "who acted, when, what resource changed, and from which IP address", fn world ->
    # Perform a real audited action through the UI (create a tag), then
    # read its audit row back: actor, timestamp, resource type, and the
    # request IP recorded in the entry's metadata.
    tag_name = "audit trail tag #{System.unique_integer([:positive])}"
    session = create_tag_via_ui(world.session, world.org, tag_name)

    log = find_audit_entry!(world.org, "tag.created", &(&1.user_id == world.operator.id))
    row = "[data-test=audit-log-row-#{log.id}]"
    timestamp = Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M")

    session =
      session
      |> visit_live("/admin/audit-log?org=#{world.org.slug}")
      |> assert_has(css("[data-test=actor-link-#{log.id}]", text: world.operator.email))
      |> assert_has(css(row, text: timestamp))
      |> assert_has(css(row, text: "Tag"))
      |> click(css("[data-test=expand-btn-#{log.id}]"))
      |> assert_has(css("[data-test=metadata-#{log.id}]", text: "\"ip\""))

    Map.put(world, :session, session)
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
    # The export runs as an inline Oban job that uploads the CSV through
    # Marquee.Storage; capture the uploaded bytes from the storage mock.
    step_pid = self()
    Mox.set_mox_global()

    Mox.stub(Marquee.Storage.MockSpacesClient, :put_object, fn key, body, _content_type ->
      send(step_pid, {:csv_uploaded, key, body})
      :ok
    end)

    session = click(world.session, css("[data-test=export-csv-btn]"))
    Map.put(world, :session, session)
  end

  then_ "a CSV file containing the filtered entries is downloaded", fn world ->
    assert_receive {:csv_uploaded, key, csv}, 5_000
    Mox.set_mox_private()

    assert String.ends_with?(key, ".csv")
    [header | rows] = String.split(csv, "\n", trim: true)
    assert String.starts_with?(header, "timestamp,actor_email,action")

    # The filter was action = video.created: only that entry is exported.
    assert rows != [], "expected the export to contain the filtered entry"
    assert Enum.all?(rows, &String.contains?(&1, ",video.created,"))
    refute Enum.any?(rows, &String.contains?(&1, ",tag.created,"))

    # The operator is handed a link to the finished file.
    assert_has(world.session, css("#flash-info", text: "Export ready"))
    assert_has(world.session, css("#flash-info", text: key))
    world
  end

  # ---- Impersonation context ------------------------------------------

  given_ "a super admin impersonated an operator and made a change", fn world ->
    super_admin = insert(:super_admin)

    {:ok, admin_session} =
      Wallaby.start_session(
        metadata: Phoenix.Ecto.SQL.Sandbox.metadata_for(Marquee.Repo, self())
      )

    tag_name = "impersonated tag #{System.unique_integer([:positive])}"

    admin_session =
      admin_session
      |> MarqueeWeb.WallabyCase.log_in_session(super_admin)
      |> visit_live("/super/organizations/#{world.org.id}")
      |> click(css("[data-test=impersonate-btn]"))
      |> assert_has(css("[data-test=impersonation-banner]"))
      |> create_tag_via_ui(world.org, tag_name)

    Wallaby.end_session(admin_session)

    log = find_audit_entry!(world.org, "tag.created", fn _ -> true end)

    Map.merge(world, %{super_admin: super_admin, impersonated_log: log})
  end

  when_ "I view the audit log entry for that change", fn world ->
    log = world.impersonated_log

    session =
      world.session
      |> visit_live("/admin/audit-log?org=#{world.org.slug}")
      |> assert_has(css("[data-test=audit-log-row-#{log.id}]"))
      |> click(css("[data-test=expand-btn-#{log.id}]"))
      |> assert_has(css("[data-test=metadata-row-#{log.id}]"))

    Map.put(world, :session, session)
  end

  then_ "I can see both the impersonating user and the acted-as user", fn world ->
    log = world.impersonated_log
    entry = "[data-test=audit-log-row-#{log.id}]"
    details = "[data-test=metadata-row-#{log.id}]"

    # The acting identity is the super admin; the entry must also say on
    # whose behalf (the impersonated organization's operator) it acted.
    assert log.metadata["impersonated_by"] == world.super_admin.id,
           "expected audit metadata to record impersonated_by #{world.super_admin.id}, " <>
             "got #{inspect(log.metadata)}"

    world.session
    |> assert_has(css("#{entry}, #{details}", text: world.super_admin.email))
    |> assert_has(css(details, text: world.operator.email))

    world
  end

  # ---- Super admin platform audit log ------------------------------------

  when_ "I navigate to /super/audit-log", fn world ->
    world = seed_platform_audit_entries(world)
    Map.put(world, :session, visit_live(world.session, "/super/audit-log"))
  end

  then_ "I see audit events across all organizations", fn world ->
    world.session
    |> assert_has(css("[data-test=audit-log-table]"))
    |> assert_has(css("[data-test=audit-log-row-#{world.log_org_a.id}]", text: world.org_a.name))
    |> assert_has(css("[data-test=audit-log-row-#{world.log_org_b.id}]", text: world.org_b.name))

    world
  end

  given_ "the platform audit log has entries from multiple organizations", fn world ->
    seed_platform_audit_entries(world)
  end

  when_ "I filter by a specific organization", fn world ->
    session =
      world.session
      |> visit_live("/super/audit-log")
      |> select_option("[data-test=filter-org]", world.org_a.id)

    Map.put(world, :session, session)
  end

  then_ "only entries from that organization are shown", fn world ->
    world.session
    |> assert_has(css("[data-test=audit-log-row-#{world.log_org_a.id}]"))
    |> refute_has(css("[data-test=audit-log-row-#{world.log_org_b.id}]"))

    world
  end

  given_ "a super admin action such as granting super admin access occurred", fn world ->
    subscriber = ensure_audit_subscriber()
    target = insert(:user, email: "promoted-#{System.unique_integer([:positive])}@example.com")

    session =
      world.session
      |> visit_live("/super/users")
      |> click(css("[data-test=grant-super-admin-#{target.id}]"))
      |> assert_has(css("[data-test=super-admin-badge-#{target.id}]"))

    Map.merge(world, %{session: session, target_user: target, audit_subscriber: subscriber})
  end

  when_ "I view the platform audit log", fn world ->
    _ = :sys.get_state(world.audit_subscriber)

    %{results: entries} = Audit.list_all(%{action: "super.admin.granted"}, per_page: 50)

    log =
      Enum.find(entries, fn e -> to_string(e.resource_id) == to_string(world.target_user.id) end)

    assert log, "expected a super.admin.granted audit entry for #{world.target_user.id}"

    session = visit_live(world.session, "/super/audit-log")
    Map.merge(world, %{session: session, grant_log: log})
  end

  then_ "that action appears as an audit entry with the super admin as actor", fn world ->
    log = world.grant_log
    stop_audit_subscriber(world.audit_subscriber)

    world.session
    |> assert_has(css("[data-test=audit-log-row-#{log.id}]", text: "super.admin.granted"))
    |> assert_has(css("[data-test=actor-link-#{log.id}]", text: world.super_admin.email))

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

  defp create_tag_via_ui(session, org, name) do
    session
    |> visit_live("/admin/tags?org=#{org.slug}")
    |> fill_in(css("[data-test=new-tag-input]"), with: name)
    |> click(css("[data-test=create-tag-btn]"))
    |> assert_has(css("[data-test=tags-list]", text: name))
  end

  defp find_audit_entry!(org, action, predicate) do
    %{results: entries} = Audit.list_for_organization(org, %{action: action}, per_page: 50)
    entry = Enum.find(entries, predicate)
    assert entry, "expected a #{action} audit entry in #{org.slug}, got #{inspect(entries)}"
    entry
  end

  defp seed_platform_audit_entries(world) do
    org_a = insert(:organization, name: "Audit Org Alpha")
    org_b = insert(:organization, name: "Audit Org Beta")
    {:ok, log_a} = Audit.log(operator_scope(org_a), "video.created", build_resource("Video"))
    {:ok, log_b} = Audit.log(operator_scope(org_b), "tag.created", build_resource("Tag"))

    # Filter options are cached globally (5-minute TTL, no invalidation) and
    # the cache is not reset between scenarios; drop any copy warmed by an
    # earlier scenario so this scenario's organizations are listed.
    Marquee.Cache.delete("audit_filter_options:global")

    Map.merge(world, %{org_a: org_a, org_b: org_b, log_org_a: log_a, log_org_b: log_b})
  end

  defp operator_scope(org) do
    user = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: user, organization: org, role: :owner)
    Scope.for_user(user) |> Scope.with_organization(org, membership)
  end

  # The application does not start AuditSubscriber in the test env
  # (lib/marquee/application.ex); tests that need it start it explicitly.
  defp ensure_audit_subscriber do
    case GenServer.start(Marquee.Events.AuditSubscriber, :ok,
           name: Marquee.Events.AuditSubscriber
         ) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  defp stop_audit_subscriber(pid) do
    GenServer.stop(pid)
  catch
    :exit, _already_stopped -> :ok
  end
end
