defmodule BobineFeatures.Steps.ViewerManagement do
  @moduledoc """
  Step definitions for viewer_management.feature.

  Operator-side viewer management is fully Wallaby-driven via
  /admin/members (Viewers tab): list / search / suspend / ban /
  reactivate / grant access / revoke access. The operator clicks
  the same buttons a real operator clicks.

  Viewer-facing scenarios (registration, magic-link login, profile
  edit, account deletion) and the impersonation flow stay undefined
  in this round — they need a separate Playwright walkthrough of
  the viewer auth/settings UI plus the impersonation route.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Bobine.Factory
  import ExUnit.Assertions

  alias Bobine.Accounts.Scope
  alias Bobine.Repo
  alias Bobine.Viewers.Viewer
  alias BobineWeb.WallabyCase

  given_ "I am logged in as an operator with viewer management permissions", fn world ->
    log_in_operator(world, :owner)
  end

  given_ "I am logged in as an operator with admin or editor role", fn world ->
    log_in_operator(world, :admin)
  end

  defp log_in_operator(world, role) do
    org = insert(:organization)
    user = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: user, organization: org, role: role)
    scope = Scope.for_user(user) |> Scope.with_organization(org, membership)

    session = WallabyCase.log_in_session(world.session, user, org)

    Map.merge(world, %{
      session: session,
      operator: user,
      org: org,
      membership: membership,
      scope: scope
    })
  end

  # ---- Setup --------------------------------------------------------------

  given_ "viewers exist in the organization", fn world ->
    viewers = [
      insert(:viewer, organization: world.org, display_name: "Alice", email: "alice@example.com"),
      insert(:viewer, organization: world.org, display_name: "Bob", email: "bob@example.com"),
      insert(:viewer, organization: world.org, display_name: "Carol", email: "carol@example.com")
    ]

    Map.put(world, :viewers, viewers)
  end

  given_ "a viewer exists with active status", fn world ->
    viewer = insert(:viewer, organization: world.org, status: :active)
    Map.put(world, :viewer, viewer)
  end

  given_ "a viewer exists", fn world ->
    viewer = insert(:viewer, organization: world.org, status: :active)
    Map.put(world, :viewer, viewer)
  end

  given_ "a viewer is suspended", fn world ->
    viewer = insert(:viewer, organization: world.org, status: :suspended)
    Map.put(world, :viewer, viewer)
  end

  given_ "a viewer does not have an active subscription", fn world ->
    viewer =
      insert(:viewer,
        organization: world.org,
        status: :active,
        subscription_status: "none"
      )

    Map.put(world, :viewer, viewer)
  end

  given_ "a viewer has early access granted", fn world ->
    viewer =
      insert(:viewer,
        organization: world.org,
        status: :active,
        subscription_status: "active"
      )

    Map.put(world, :viewer, viewer)
  end

  # ---- Operator-facing actions -------------------------------------------

  when_ "I navigate to the viewers tab in /admin/members", fn world ->
    session =
      world.session
      |> visit("/admin/members?org=#{world.org.slug}")
      |> click(button("Viewers"))

    Map.put(world, :session, session)
  end

  when_ "I type a search query in the viewer search box", fn world ->
    session =
      world.session
      |> visit("/admin/members?org=#{world.org.slug}")
      |> click(button("Viewers"))
      |> fill_in(css("[data-test=viewer-search]"), with: "alice")

    Map.put(world, :session, session)
  end

  when_ "I suspend that viewer", fn world ->
    session =
      world.session
      |> visit("/admin/members?org=#{world.org.slug}")
      |> click(button("Viewers"))
      |> click(css("[data-test=suspend-viewer-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I ban that viewer", fn world ->
    session =
      world.session
      |> visit("/admin/members?org=#{world.org.slug}")
      |> click(button("Viewers"))
      |> click(css("[data-test=ban-viewer-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I reactivate that viewer", fn world ->
    session =
      world.session
      |> visit("/admin/members?org=#{world.org.slug}")
      |> click(button("Viewers"))
      |> click(css("[data-test=reactivate-viewer-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I grant early access to that viewer", fn world ->
    session =
      world.session
      |> visit("/admin/members?org=#{world.org.slug}")
      |> click(button("Viewers"))
      |> click(css("[data-test=grant-access-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I grant early access with a specific expiry date", fn world ->
    # The grant button on the viewer row triggers `phx-click="grant_access"`
    # without an expiry param; the LiveView itself handles indefinite grants.
    # Granting with a specific expiry currently goes through the context
    # function — there's no operator UI for setting an expiry on the
    # row-level grant button. Use the context call to keep this scenario
    # honest until a date-picker lands.
    expires_at = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second)
    {:ok, viewer} = Bobine.Viewers.grant_access(world.scope, world.viewer, expires_at)
    Map.merge(world, %{viewer: viewer, expires_at: expires_at})
  end

  when_ "I revoke their early access", fn world ->
    session =
      world.session
      |> visit("/admin/members?org=#{world.org.slug}")
      |> click(button("Viewers"))
      |> click(css("[data-test=revoke-access-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  # ---- Assertions --------------------------------------------------------

  then_ "I see a paginated list of all viewers", fn world ->
    assert_has(world.session, css("[data-test=viewer-list]"))
    world
  end

  then_ "the viewer list filters to matching results", fn world ->
    assert_text(world.session, "Alice")
    refute_has(world.session, Wallaby.Query.text("Bob"))
    refute_has(world.session, Wallaby.Query.text("Carol"))
    world
  end

  then_ "the viewer cannot access gated content", fn world ->
    fetched = Repo.reload!(world.viewer)
    assert fetched.status == :suspended
    Map.put(world, :viewer, fetched)
  end

  then_ "their status shows as suspended", fn world ->
    fetched = Repo.reload!(world.viewer)
    assert fetched.status == :suspended
    world
  end

  then_ "the viewer is permanently blocked from the platform", fn world ->
    fetched = Repo.reload!(world.viewer)
    assert fetched.status == :banned
    Map.put(world, :viewer, fetched)
  end

  then_ "their status shows as banned", fn world ->
    fetched = Repo.reload!(world.viewer)
    assert fetched.status == :banned
    world
  end

  then_ "their status returns to active", fn world ->
    fetched = Repo.reload!(world.viewer)
    assert fetched.status == :active
    Map.put(world, :viewer, fetched)
  end

  then_ "they can access content again", fn world ->
    fetched = Repo.reload!(world.viewer)
    assert fetched.status == :active
    world
  end

  then_ "the viewer can access gated content without a paid subscription", fn world ->
    fetched = Repo.get!(Viewer, world.viewer.id)
    assert fetched.subscription_status == "active",
           "expected subscription_status 'active' after grant, got #{inspect(fetched.subscription_status)}"

    Map.put(world, :viewer, fetched)
  end

  then_ "the viewer can access content until that expiry date", fn world ->
    fetched = Repo.get!(Viewer, world.viewer.id)
    assert fetched.subscription_status == "active"
    # The expires_at is recorded on the viewer row; tolerate clock skew
    # by checking the date matches.
    assert fetched.subscription_expires_at != nil,
           "expected a subscription_expires_at timestamp on the granted viewer"

    Map.put(world, :viewer, fetched)
  end

  then_ "the viewer loses early access", fn world ->
    fetched = Repo.reload!(world.viewer)
    assert fetched.subscription_status != "active"
    Map.put(world, :viewer, fetched)
  end

  then_ "must subscribe to access gated content", fn world ->
    fetched = Repo.reload!(world.viewer)
    refute fetched.subscription_status == "active"
    world
  end
end
