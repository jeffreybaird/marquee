defmodule MarqueeFeatures.Steps.Authentication do
  @moduledoc """
  Step definitions for authentication.feature.

  All steps drive the actual UI via Wallaby. `Given I have a confirmed
  operator account` sets up DB state (a pragmatic concession — onboarding
  each test user via the full magic-link flow would be gratuitously slow),
  but every `When`/`Then` here exercises the live login/logout forms.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions

  alias Marquee.Accounts
  alias Marquee.AccountsFixtures
  alias Marquee.Accounts.Organization
  alias Marquee.Repo

  # ---- Registration -------------------------------------------------------

  given_ "I am an unauthenticated user", fn world ->
    world
  end

  when_ "I submit the registration form with a valid email and organization name", fn world ->
    email = "operator#{System.unique_integer([:positive])}@example.com"
    org_name = "Acme #{System.unique_integer([:positive])}"

    session =
      world.session
      |> visit("/users/register")
      |> fill_in(css("[data-test=registration-org-name]"), with: org_name)
      |> fill_in(css("[data-test=registration-email]"), with: email)
      |> click(css("[data-test=registration-submit]"))

    Map.merge(world, %{session: session, email: email, org_name: org_name})
  end

  then_ "I see instructions to confirm my account", fn world ->
    assert_text(world.session, "An email was sent to #{world.email}")
    world
  end

  then_ "an unconfirmed operator account exists for my email", fn world ->
    user = Accounts.get_user_by_email(world.email)
    assert user, "expected a user with email #{world.email}"
    assert is_nil(user.confirmed_at), "expected user to be unconfirmed"
    Map.put(world, :registered_user, user)
  end

  then_ "my organization has an auto-generated slug derived from its name", fn world ->
    org = Repo.get_by!(Organization, name: world.org_name)
    assert org.slug != ""
    assert org.slug =~ ~r/^[a-z0-9-]+$/
    Map.put(world, :registered_org, org)
  end

  when_ "I open the magic link I received", fn world ->
    {encoded_token, _raw_token} =
      AccountsFixtures.generate_user_magic_link_token(world.registered_user)

    session =
      visit(
        world.session,
        "/users/log-in/#{encoded_token}?org=#{world.registered_org.slug}"
      )

    Map.put(world, :session, session)
  end

  when_ "I choose to stay logged in", fn world ->
    # The confirm button is a `phx-trigger-action` submit: the real POST that
    # sets the session cookie lands after Wallaby's click returns. The
    # signed-in redirect sends a brand-new owner to /admin, whose onboarding
    # gate pushes straight on to the setup wizard — wait for its heading so
    # the following assertions run against the post-login document.
    session =
      world.session
      |> click(button("Confirm and stay logged in"))
      |> assert_has(css("#onboarding-heading"))

    Map.put(world, :session, session)
  end

  then_ "I am taken to onboarding for my new organization", fn world ->
    # A freshly registered organization has not completed onboarding, so the
    # dashboard gate lands the new owner on the setup wizard for their org.
    session =
      world.session
      |> assert_has(css("#onboarding-heading", text: "Welcome to #{world.org_name}"))
      |> assert_has(css("[data-test=onboarding-progress]"))
      |> assert_has(css("body", text: world.email))

    assert current_path(session) == "/admin/onboarding"

    Map.put(world, :session, session)
  end

  # ---- Login --------------------------------------------------------------

  given_ "I have a confirmed operator account", fn world ->
    Map.merge(world, confirmed_operator_with_org())
  end

  given_ "I have a confirmed operator account with a password", fn world ->
    password = AccountsFixtures.valid_user_password()
    setup = confirmed_operator_with_org()
    {:ok, {user, _tokens}} = Accounts.update_user_password(setup.operator, %{password: password})

    world
    |> Map.merge(%{setup | operator: user})
    |> Map.put(:password, password)
  end

  when_ "I submit my email and password on the login page", fn world ->
    # The login page ships two forms — the magic-link form above the "or"
    # divider (#login_form_magic) and the password form below it
    # (#login_form_password). Target each via its form-scoped field id.
    session =
      world.session
      |> visit("/users/log-in")
      |> fill_in(css("#login_form_password_email"), with: world.operator.email)
      |> fill_in(css("#user_password"), with: world.password)
      |> click(button("Log in and stay logged in"))

    Map.put(world, :session, session)
  end

  when_ "I submit my email and an incorrect password on the login page", fn world ->
    session =
      world.session
      |> visit("/users/log-in")
      |> fill_in(css("#login_form_password_email"), with: world.operator.email)
      |> fill_in(css("#user_password"), with: "wrong-password-12345")
      |> click(button("Log in and stay logged in"))

    Map.put(world, :session, session)
  end

  when_ "I submit only my email on the login page", fn world ->
    session =
      world.session
      |> visit("/users/log-in")
      |> fill_in(css("#login_form_magic_email"), with: world.operator.email)
      |> click(button("Log in with email"))

    Map.put(world, :session, session)
  end

  then_ "I am on the admin dashboard", fn world ->
    # Password login is a full-page POST + redirect; query the heading rather
    # than a cached <body> so the poll survives the document swap.
    session = assert_has(world.session, css("h1", text: "Dashboard"))
    assert current_path(session) == "/admin"
    Map.put(world, :session, session)
  end

  then_ "I remain on the login page", fn world ->
    assert current_path(world.session) =~ ~r{^/users/log-in}
    world
  end

  then_ "I see instructions that a log-in link has been sent", fn world ->
    assert_has(
      world.session,
      css("#flash-info", text: "you will receive instructions for logging in shortly")
    )

    world
  end

  # ---- Logout -------------------------------------------------------------

  when_ "I log out", fn world ->
    # The sidebar "Log out" link uses Phoenix's deleteable link helper;
    # Wallaby follows the click and the server issues the delete action.
    session = click(world.session, link("Log out"))
    Map.put(world, :session, session)
  end

  # ---- Private helpers ----------------------------------------------------

  # An operator is a confirmed user who owns an established organization;
  # without a membership the signed-in redirect lands on the public home page
  # rather than the admin dashboard.
  defp confirmed_operator_with_org do
    org = insert(:organization)
    user = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: user, organization: org, role: :owner)
    %{operator: user, org: org, membership: membership}
  end
end
