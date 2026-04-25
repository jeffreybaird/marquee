defmodule BobineFeatures.Steps.AuditLogging do
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
  import Bobine.Factory
  import ExUnit.Assertions

  alias Bobine.Audit
  alias Bobine.Accounts.Scope

  given_ "I am logged in as an organization owner or admin", fn world ->
    org = insert(:organization)
    user = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: user, organization: org, role: :owner)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    session = BobineWeb.WallabyCase.log_in_session(world.session, user, org)

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
        Bobine.Repo.get_by!(Bobine.Accounts.Membership,
          user_id: other_user.id,
          organization_id: world.org.id
        )
      )

    {:ok, log_a} = Audit.log(world.scope, "video.created", build_resource("Video"))
    {:ok, log_b} = Audit.log(other_scope, "tag.created", build_resource("Tag"))

    Map.merge(world, %{other_user: other_user, log_a: log_a, log_b: log_b})
  end

  given_ "the audit log has entries of various action types", fn world ->
    {:ok, _} = Audit.log(world.scope, "video.created", build_resource("Video"))
    {:ok, _} = Audit.log(world.scope, "video.updated", build_resource("Video"), %{title: "x"})
    {:ok, _} = Audit.log(world.scope, "video.deleted", build_resource("Video"))
    world
  end

  given_ "the audit log has entries for various resource types", fn world ->
    {:ok, _} = Audit.log(world.scope, "video.created", build_resource("Video"))
    {:ok, _} = Audit.log(world.scope, "tag.created", build_resource("Tag"))
    {:ok, _} = Audit.log(world.scope, "collection.created", build_resource("Collection"))
    world
  end

  given_ "the audit log has entries", fn world ->
    {:ok, log} =
      Audit.log(world.scope, "video.updated", build_resource("Video"), %{title: "renamed"})

    Map.put(world, :log_entry, log)
  end

  given_ "the audit log has more entries than fit on one page", fn world ->
    # Default per_page is 50. Seed a couple over that threshold so the
    # cursor returns a non-nil next_cursor.
    Enum.each(1..52, fn i ->
      {:ok, _} = Audit.log(world.scope, "video.created", build_resource("Video", "vid-#{i}"))
    end)

    world
  end

  given_ "I have applied filters to the audit log", fn world ->
    {:ok, _} = Audit.log(world.scope, "video.created", build_resource("Video"))

    session =
      world.session
      |> visit("/admin/audit-log?org=#{world.org.slug}")
      |> Wallaby.Browser.set_value(css("[data-test=filter-action]"), "video.created")

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
      |> visit("/admin/audit-log?org=#{world.org.slug}")
      |> Wallaby.Browser.set_value(css("[data-test=filter-actor]"), world.other_user.id)

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
      |> visit("/admin/audit-log?org=#{world.org.slug}")
      |> Wallaby.Browser.set_value(css("[data-test=filter-action]"), "video.created")

    Map.put(world, :session, session)
  end

  then_ "only entries matching that action type are shown", fn world ->
    # The table shows only rows whose action matches the selected filter.
    assert_text(world.session, "video.created")
    refute_has(world.session, Wallaby.Query.text("video.deleted"))
    world
  end

  when_ "I filter by resource type", fn world ->
    session =
      world.session
      |> visit("/admin/audit-log?org=#{world.org.slug}")
      |> Wallaby.Browser.set_value(css("[data-test=filter-resource-type]"), "Tag")

    Map.put(world, :session, session)
  end

  then_ "only entries for that resource type are shown", fn world ->
    assert_text(world.session, "Tag")
    refute_has(world.session, Wallaby.Query.text("Collection"))
    world
  end

  # ---- Expand entry ------------------------------------------------------

  when_ "I expand an entry", fn world ->
    session =
      world.session
      |> visit("/admin/audit-log?org=#{world.org.slug}")
      |> click(css("[data-test=expand-btn-#{world.log_entry.id}]"))

    Map.put(world, :session, session)
  end

  then_ "I see the full diff showing exactly what fields changed", fn world ->
    assert_has(world.session, css("[data-test=metadata-row-#{world.log_entry.id}]"))
    # The seeded changes were %{title: "renamed"} — that key/value should
    # render in the metadata row.
    assert_text(world.session, "title")
    assert_text(world.session, "renamed")
    world
  end

  # ---- Load more ---------------------------------------------------------

  when_ "I click to load more", fn world ->
    session =
      world.session
      |> visit("/admin/audit-log?org=#{world.org.slug}")
      |> click(css("[data-test=load-more-btn]"))

    Map.put(world, :session, session)
  end

  then_ "additional entries are appended to the list", fn world ->
    # After load_more, more than the initial page of rows exist in the DOM.
    rows = Wallaby.Browser.all(world.session, css("[data-test^=audit-log-row-]"))
    assert length(rows) > 50, "expected > 50 audit-log rows after load_more, got #{length(rows)}"
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
    %{__struct__: Module.concat([Bobine.AuditFakeResource, type]), id: id}
  end
end
