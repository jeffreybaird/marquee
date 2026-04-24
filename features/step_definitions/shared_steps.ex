defmodule BobineFeatures.Steps.Shared do
  @moduledoc """
  Cross-feature step definitions: login, navigation, generic assertions.

  Helpers that appear in more than one feature file live here so each
  domain-specific step module can focus on its own verbs.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Bobine.Factory
  import ExUnit.Assertions

  alias Bobine.Accounts.Scope
  alias BobineWeb.WallabyCase

  # ---- Background ---------------------------------------------------------

  given_ "the Bobine platform is running", fn world ->
    world
  end

  # ---- Login --------------------------------------------------------------

  given_ "I am logged in as an operator", fn world ->
    log_in_as_operator(world, :owner)
  end

  given_ "I am logged in as an operator with content management permissions", fn world ->
    log_in_as_operator(world, :owner)
  end

  given_ "I am logged in as an operator with the owner role", fn world ->
    log_in_as_operator(world, :owner)
  end

  given_ "I am logged in as an operator with the admin role", fn world ->
    log_in_as_operator(world, :admin)
  end

  given_ "I am logged in as an operator with the editor role", fn world ->
    log_in_as_operator(world, :editor)
  end

  given_ "I am logged in as an organization owner", fn world ->
    log_in_as_operator(world, :owner)
  end

  # ---- Navigation ---------------------------------------------------------

  # `I am on the admin dashboard` is defined in authentication_steps.ex as a
  # Then assertion after login. Add a distinct Given here if a scenario needs
  # to navigate to the dashboard as setup (e.g. "Given I have navigated to
  # the admin dashboard").

  given_ "I am on the content page", fn world ->
    session = visit(world.session, "/admin/content?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  given_ "I am on the collections page", fn world ->
    session = visit(world.session, "/admin/collections?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  given_ "I am on the series page", fn world ->
    session = visit(world.session, "/admin/series?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  given_ "I am on the tags page", fn world ->
    session = visit(world.session, "/admin/tags?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  given_ "I am on the catalog management page", fn world ->
    session = visit(world.session, "/admin/catalog?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  given_ "I am on the members page", fn world ->
    session = visit(world.session, "/admin/members?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  given_ "I am on the settings page", fn world ->
    session = visit(world.session, "/admin/settings?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  given_ "I am on the audit log page", fn world ->
    session = visit(world.session, "/admin/audit-log?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  given_ "I am on the appearance settings page", fn world ->
    session = visit(world.session, "/admin/appearance?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  # ---- Generic assertions -------------------------------------------------

  then_ "I see {string}", fn world, text ->
    assert_text(world.session, text)
    world
  end

  then_ "I do not see {string}", fn world, text ->
    refute_has(world.session, Wallaby.Query.text(text))
    world
  end

  then_ "I see a flash saying {string}", fn world, text ->
    assert_text(world.session, text)
    world
  end

  then_ "I am on the path {string}", fn world, path ->
    assert current_path(world.session) == path
    world
  end

  # ---- Private helpers ----------------------------------------------------

  defp log_in_as_operator(world, role) do
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
end
