defmodule BobineFeatures.Steps.Authentication do
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
  import Bobine.Factory
  import ExUnit.Assertions

  alias Bobine.Accounts
  alias Bobine.AccountsFixtures
  alias Bobine.Organizations.Organization
  alias Bobine.Repo

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
    session = click(world.session, button("Confirm and stay logged in"))
    Map.put(world, :session, session)
  end

  then_ "I am on the admin dashboard for my new organization", fn world ->
    session = visit(world.session, "/admin?org=#{world.registered_org.slug}")

    session
    |> assert_text("Dashboard")
    |> assert_text(world.org_name)
    |> assert_text(world.email)

    Map.put(world, :session, session)
  end

  # ---- Login --------------------------------------------------------------

  given_ "I have a confirmed operator account", fn world ->
    user = insert(:user, confirmed_at: DateTime.utc_now())
    Map.put(world, :operator, user)
  end

  given_ "I have a confirmed operator account with a password", fn world ->
    password = AccountsFixtures.valid_user_password()
    user = insert(:user, confirmed_at: DateTime.utc_now())
    {:ok, {user, _tokens}} = Accounts.update_user_password(user, %{password: password})
    Map.merge(world, %{operator: user, password: password})
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
    assert_text(world.session, "Dashboard")
    world
  end

  then_ "I remain on the login page", fn world ->
    assert current_path(world.session) =~ ~r{^/users/log-in}
    world
  end

  then_ "I see instructions that a log-in link has been sent", fn world ->
    assert_text(world.session, "A link to log in has been sent")
    world
  end

  # ---- Logout -------------------------------------------------------------

  when_ "I log out", fn world ->
    # The sidebar "Log out" link uses Phoenix's deleteable link helper;
    # Wallaby follows the click and the server issues the delete action.
    session = click(world.session, link("Log out"))
    Map.put(world, :session, session)
  end

  then_ "I am on the log-in page", fn world ->
    assert current_path(world.session) == "/users/log-in"
    world
  end
end
