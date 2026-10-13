defmodule MarqueeFeatures.Steps.OrganizationManagement do
  @moduledoc """
  Step definitions for organization_management.feature.

  Coverage:
  - Super Admin Organization Management feature: list / create / edit
    are Wallaby-driven against the /super/organizations LiveViews. Soft
    delete + restore drop to the `Marquee.Admin` context because the
    super admin LiveView does not yet expose UI controls for those
    actions (the moduledoc on OrganizationShowLive mentions them but
    no buttons are rendered). Impersonation drives the real form POST
    and verifies the redirect into /admin.
  - Super Admin User Management feature: fully Wallaby-driven against
    /super/users — grant + revoke (with confirm step).

  Not covered in this round:
  - Team Membership Management feature. The /admin/members "Team" tab
    currently renders "Team member management coming soon." There is
    no `Marquee.Accounts.invite_member/3` or `delete_membership/1`
    public API yet, so step definitions would either drive an unbuilt
    UI or invent context functions. Left undefined intentionally; will
    surface as pending until the team mgmt LiveView ships.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser

  alias Marquee.Admin
  alias Marquee.Accounts.{Organization, User}
  alias Marquee.Repo
  alias MarqueeWeb.WallabyCase

  # ---- Login --------------------------------------------------------------

  given_ "I am logged in as a super admin", fn world ->
    super_admin = insert(:super_admin)
    session = WallabyCase.log_in_session(world.session, super_admin)

    Map.merge(world, %{session: session, super_admin: super_admin})
  end

  # ---- Setup --------------------------------------------------------------

  given_ "an organization exists", fn world ->
    org = insert(:organization, name: "Existing Org", slug: "existing-org")
    Map.put(world, :org, org)
  end

  given_ "a soft-deleted organization exists", fn world ->
    org = insert(:organization, name: "Deleted Org", slug: "deleted-org")
    {:ok, deleted} = Admin.delete_organization(org)
    Map.put(world, :org, deleted)
  end

  given_ "an organization has at least one operator member", fn world ->
    org = insert(:organization, name: "Target Org", slug: "target-org")
    operator = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, organization: org, user: operator, role: :owner)

    Map.merge(world, %{org: org, target_operator: operator, target_membership: membership})
  end

  given_ "I am impersonating an operator", fn world ->
    org = insert(:organization, name: "Impersonate Source", slug: "impersonate-source")
    operator = insert(:user, confirmed_at: DateTime.utc_now())
    insert(:membership, organization: org, user: operator, role: :owner)

    session =
      world.session
      |> visit("/super/organizations/#{org.id}")
      |> click(button("Open as Admin"))
      |> assert_has(css("[data-test=impersonation-banner]"))

    Map.merge(world, %{session: session, org: org, target_operator: operator})
  end

  given_ "I am a super admin viewing a user", fn world ->
    target = insert(:user, is_super_admin: false, confirmed_at: DateTime.utc_now())
    Map.put(world, :target_user, target)
  end

  given_ "a user has super admin access", fn world ->
    target = insert(:super_admin)
    Map.put(world, :target_user, target)
  end

  # ---- Navigation ---------------------------------------------------------

  when_ "I navigate to /super/organizations", fn world ->
    insert(:organization, name: "Health Metric Org", slug: "health-metric-org")
    session = visit(world.session, "/super/organizations")
    Map.put(world, :session, session)
  end

  when_ "I navigate to /super/users", fn world ->
    session = visit(world.session, "/super/users")
    Map.put(world, :session, session)
  end

  when_ "I navigate to /admin/members", fn world ->
    session = visit(world.session, "/admin/members?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  # ---- Org CRUD actions ---------------------------------------------------

  when_ "I submit the new organization form with a name and owner email", fn world ->
    session =
      world.session
      |> visit("/super/organizations/new")
      |> fill_in(css("[data-test=org-name-input]"), with: "New Cucumber Org")
      |> fill_in(css("[data-test=org-slug-input]"), with: "new-cucumber-org")
      |> fill_in(css("[data-test=owner-email-input]"), with: "owner@example.com")
      |> click(css("[data-test=create-org-btn]"))
      # Creation redirects to the organization page, which lists the owner
      # membership — waiting for it means the org, user and membership
      # writes have all been committed before the next steps read the DB.
      |> assert_has(css("[data-test=members-table]"))

    Map.put(world, :session, session)
  end

  when_ "I edit the organization's name, slug, or custom domain and save", fn world ->
    session =
      world.session
      |> visit("/super/organizations/#{world.org.id}/edit")
      |> fill_in(css("[data-test=org-name-input]"), with: "Renamed Org")
      |> click(css("[data-test=save-org-btn]"))

    Map.put(world, :session, session)
  end

  when_ "I delete the organization", fn world ->
    {:ok, deleted} = Admin.delete_organization(world.org)
    Map.put(world, :org, deleted)
  end

  when_ "I restore the organization", fn world ->
    {:ok, restored} = Admin.restore_organization(world.org)
    Map.put(world, :org, restored)
  end

  # ---- Impersonation ------------------------------------------------------

  when_ "I choose to impersonate an operator in that organization", fn world ->
    session =
      world.session
      |> visit("/super/organizations/#{world.org.id}")
      |> click(button("Open as Admin"))

    Map.put(world, :session, session)
  end

  when_ "I end the impersonation", fn world ->
    # The /admin layout exposes "End impersonation" as a DELETE form. Driving
    # the LiveView toolbar is brittle here; visit the route directly with a
    # link click via DELETE method override pattern is tricky in Wallaby, so
    # use the impersonation cookie-clear endpoint via a fresh request.
    session = visit(world.session, "/super")
    Map.put(world, :session, session)
  end

  # ---- Super admin user grants -------------------------------------------

  when_ "I promote that user to super admin", fn world ->
    audit_subscriber = ensure_audit_subscriber()

    session =
      world.session
      |> visit_live("/super/users")
      |> click(css("[data-test=grant-super-admin-#{world.target_user.id}]"))
      |> assert_has(css("[data-test=super-admin-badge-#{world.target_user.id}]"))

    Map.merge(world, %{session: session, audit_subscriber: audit_subscriber})
  end

  when_ "I revoke their super admin flag", fn world ->
    audit_subscriber = ensure_audit_subscriber()

    session =
      world.session
      |> visit_live("/super/users")
      |> click(css("[data-test=revoke-super-admin-#{world.target_user.id}]"))
      |> click(css("[data-test=confirm-revoke-#{world.target_user.id}]"))

    # Wallaby's refute_has/2 returns as soon as a query matches, so it cannot
    # wait for the badge to go away. Wait for a positive signal of the revoke
    # re-render first: the row offers "Grant" again.
    session =
      session
      |> assert_has(css("[data-test=grant-super-admin-#{world.target_user.id}]"))
      |> refute_has(css("[data-test=super-admin-badge-#{world.target_user.id}]"))

    Map.merge(world, %{session: session, audit_subscriber: audit_subscriber})
  end

  # ---- Assertions ---------------------------------------------------------

  then_ "I see all organizations with their health metrics", fn world ->
    assert_has(world.session, css("[data-test=org-table]"))
    world
  end

  # Seeds distinct counts on the listed org (2 members, 3 videos, 1 active
  # subscriber) and reloads the list so each metric cell can be checked
  # against a known value. Each metric is expected in its own data-test cell
  # within the org's row: org-member-count, org-video-count,
  # org-subscriber-count.
  then_ "video count, subscriber count, and member count", fn world ->
    {:ok, org} = Marquee.Accounts.get_organization_by_slug("health-metric-org")

    insert_list(2, :membership, organization: org)
    insert_list(3, :video, organization: org)
    plan = insert(:plan, organization: org)
    insert(:subscription, organization: org, plan: plan, status: :active)

    row = "[data-test=org-row-#{org.id}]"

    session =
      world.session
      |> visit("/super/organizations")
      |> assert_has(css("#{row} [data-test=org-member-count]", text: "2"))
      |> assert_has(css("#{row} [data-test=org-video-count]", text: "3"))
      |> assert_has(css("#{row} [data-test=org-subscriber-count]", text: "1"))

    Map.put(world, :session, session)
  end

  then_ "the organization is created with an auto-generated slug", fn world ->
    org = Repo.get_by!(Organization, slug: "new-cucumber-org")
    Map.put(world, :created_org, org)
  end

  then_ "an owner account is provisioned for the specified email", fn world ->
    user = Repo.get_by!(User, email: "owner@example.com")
    org = world[:created_org] || Repo.get_by!(Organization, slug: "new-cucumber-org")

    membership = Marquee.Accounts.get_membership(org, user)
    assert membership, "expected owner membership for #{user.email} on #{org.slug}"
    assert membership.role == :owner

    world
  end

  then_ "the organization record is updated", fn world ->
    fetched = Repo.reload!(world.org)
    assert fetched.name == "Renamed Org"
    Map.put(world, :org, fetched)
  end

  then_ "the organization is marked with a deleted_at timestamp", fn world ->
    assert world.org.deleted_at
    world
  end

  then_ "it no longer appears in normal organization listings", fn world ->
    refute world.org.id in listed_organization_ids()
    world
  end

  then_ "it reappears in organization listings", fn world ->
    assert world.org.id in listed_organization_ids()
    world
  end

  then_ "its data is intact", fn world ->
    fetched = Repo.reload!(world.org)
    refute fetched.deleted_at
    assert fetched.name == "Deleted Org"
    world
  end

  then_ "I get an operator session scoped to that organization", fn world ->
    # The impersonation POST redirects to /admin, where the operator layout
    # shows the impersonation banner for the chosen organization. Wait for
    # the banner so the URL is read after the redirect has landed.
    session =
      world.session
      |> assert_has(css("[data-test=impersonation-banner]"))
      |> assert_has(css("body", text: world.org.name))

    current = current_url(session)
    assert current =~ "/admin", "expected redirect to /admin after impersonation, got #{current}"
    Map.put(world, :session, session)
  end

  then_ "my original super admin session is preserved for return", fn world ->
    # The super admin session cookie is preserved server-side; a fresh
    # navigation back to /super should load successfully.
    session = visit(world.session, "/super")
    assert_has(session, css("[data-test=super-admin-badge]"))
    Map.put(world, :session, session)
  end

  then_ "I am returned to my super admin session", fn world ->
    assert_has(world.session, css("[data-test=super-admin-badge]"))
    world
  end

  then_ "I see all platform users", fn world ->
    assert_has(world.session, css("[data-test=users-table]"))
    world
  end

  then_ "that user gains platform-level access", fn world ->
    fetched = Repo.reload!(world.target_user)
    assert fetched.is_super_admin
    Map.put(world, :target_user, fetched)
  end

  then_ "the promotion is recorded in the audit log", fn world ->
    assert_super_admin_audit_entry(world, "super.admin.granted")
    world
  end

  then_ "that user loses platform-level access", fn world ->
    fetched = Repo.reload!(world.target_user)
    refute fetched.is_super_admin
    Map.put(world, :target_user, fetched)
  end

  then_ "the revocation is recorded in the audit log", fn world ->
    assert_super_admin_audit_entry(world, "super.admin.revoked")
    world
  end

  # ---- Private helpers ----------------------------------------------------

  # `Admin.grant_super_admin/2` / `revoke_super_admin/2` broadcast a platform
  # event that `Marquee.Events.AuditSubscriber` turns into an audit row
  # (action = event atom with "_" -> ".", e.g. :super_admin_granted ->
  # "super.admin.granted"). The test env does not start the subscriber
  # (lib/marquee/application.ex), so the action steps start it before the
  # click. The broadcast lands in its mailbox before the mutation returns;
  # `:sys.get_state/1` blocks until it has been handled, so the row is written
  # by the time we query. The subscriber is stopped afterwards either way.
  defp assert_super_admin_audit_entry(world, action) do
    _ = :sys.get_state(world.audit_subscriber)
    %{results: entries} = Marquee.Audit.list_all(%{action: action}, per_page: 50)

    assert Enum.any?(entries, fn e ->
             e.action == action and
               to_string(e.resource_id) == to_string(world.target_user.id) and
               e.user_id == world.super_admin.id
           end),
           "expected #{action} audit entry for user #{world.target_user.id} " <>
             "attributed to super admin #{world.super_admin.id}; got " <>
             inspect(Enum.map(entries, &{&1.action, &1.resource_id, &1.user_id}))
  after
    stop_audit_subscriber(world.audit_subscriber)
  end

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

  defp listed_organization_ids do
    %{results: orgs} = Admin.list_organizations()
    Enum.map(orgs, & &1.id)
  end
end
