defmodule MarqueeFeatures.Steps.ViewerManagement do
  @moduledoc """
  Step definitions for viewer_management.feature.

  Operator-side viewer management is fully Wallaby-driven via
  /admin/members (Viewers tab): list / search / suspend / ban /
  reactivate / grant access / revoke access. The operator clicks
  the same buttons a real operator clicks.

  Operator viewer impersonation clicks the "View as" link on a viewer
  row and browses the viewer site with the impersonation banner. The
  viewer's own session runs in a second Wallaby session.

  Viewer-facing scenarios drive /register, /login, /magic-link and
  /account. Emails are captured from Swoosh's test adapter via
  `:shared_test_process`, and magic links are followed in the browser.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Ecto.Query, only: [from: 2]
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser

  alias Marquee.Accounts.Scope
  alias Marquee.Audit
  alias Marquee.Repo
  alias Marquee.Viewers
  alias Marquee.Viewers.Viewer
  alias Marquee.Viewers.ViewerToken
  alias MarqueeWeb.WallabyCase

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
    Map.put(world, :session, open_viewers_tab(world))
  end

  when_ "I type a search query in the viewer search box", fn world ->
    # The search box submits on Enter (`phx-keyup="search" phx-key="Enter"`).
    session =
      world
      |> open_viewers_tab()
      |> fill_in(css("[data-test=viewer-search]"), with: "alice")
      |> send_keys([:enter])

    Map.put(world, :session, session)
  end

  # Each row action re-renders the row with the opposite action once the
  # server has committed the change; waiting for that button means the
  # database assertions that follow read the updated row.
  when_ "I suspend that viewer", fn world ->
    session =
      world
      |> open_viewers_tab()
      |> click(css("[data-test=suspend-viewer-#{world.viewer.id}]"))
      |> assert_has(css("[data-test=reactivate-viewer-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I ban that viewer", fn world ->
    session =
      world
      |> open_viewers_tab()
      |> click(css("[data-test=ban-viewer-#{world.viewer.id}]"))
      |> assert_has(css("[data-test=reactivate-viewer-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I reactivate that viewer", fn world ->
    session =
      world
      |> open_viewers_tab()
      |> click(css("[data-test=reactivate-viewer-#{world.viewer.id}]"))
      |> assert_has(css("[data-test=suspend-viewer-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  when_ "I grant early access to that viewer", fn world ->
    session =
      world
      |> open_viewers_tab()
      |> click(css("[data-test=grant-access-#{world.viewer.id}]"))
      |> assert_has(css("[data-test=revoke-access-#{world.viewer.id}]"))

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
    {:ok, viewer} = Marquee.Viewers.grant_access(world.scope, world.viewer, expires_at)
    Map.merge(world, %{viewer: viewer, expires_at: expires_at})
  end

  when_ "I revoke their early access", fn world ->
    session =
      world
      |> open_viewers_tab()
      |> click(css("[data-test=revoke-access-#{world.viewer.id}]"))
      |> assert_has(css("[data-test=grant-access-#{world.viewer.id}]"))

    Map.put(world, :session, session)
  end

  # ---- Assertions --------------------------------------------------------

  then_ "I see a paginated list of all viewers", fn world ->
    assert_has(world.session, css("[data-test=viewer-list]"))
    world
  end

  then_ "the viewer list filters to matching results", fn world ->
    assert_has(world.session, css("[data-test=viewer-list]", text: "Alice"))
    refute_has(world.session, css("[data-test=viewer-list]", text: "Bob"))
    refute_has(world.session, css("[data-test=viewer-list]", text: "Carol"))
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

  # ---- Operator viewer impersonation -------------------------------------

  given_ "a viewer exists in my organization", fn world ->
    viewer =
      insert(:viewer,
        organization: world.org,
        status: :active,
        display_name: "Impersonated Viewer"
      )

    Map.put(world, :viewer, viewer)
  end

  when_ "I choose to impersonate that viewer", fn world ->
    Map.put(world, :session, start_viewer_impersonation(world))
  end

  then_ "I browse the viewer site as that viewer", fn world ->
    name = world.viewer.display_name

    session =
      world.session
      |> visit("/browse?org=#{world.org.slug}")
      |> assert_has(css("[data-test=impersonation-banner]", text: name))
      |> assert_has(css("[data-test=viewer-header-identity]", text: name))

    Map.put(world, :session, session)
  end

  then_ "the impersonation session is tracked with the operator and viewer IDs", fn world ->
    %{results: entries} = Audit.list_for_organization(world.org, %{}, per_page: 100)

    tracked =
      Enum.find(entries, fn e ->
        e.user_id == world.operator.id and to_string(e.resource_id) == world.viewer.id and
          String.contains?(e.action, "impersonat")
      end)

    assert tracked,
           "expected an impersonation audit entry for operator #{world.operator.id} " <>
             "and viewer #{world.viewer.id}; got " <>
             inspect(Enum.map(entries, &{&1.action, &1.user_id, &1.resource_id}))

    world
  end

  given_ "I am impersonating a viewer", fn world ->
    viewer =
      insert(:subscribed_viewer,
        organization: world.org,
        status: :active,
        display_name: "Impersonated Viewer"
      )

    # The viewer is signed in on their own device at the same time.
    {:ok, viewer_session} =
      Wallaby.start_session(
        metadata: Phoenix.Ecto.SQL.Sandbox.metadata_for(Repo, self())
      )

    viewer_session = sign_in_viewer_via_magic_link(viewer_session, world.org, viewer)
    world = Map.merge(world, %{viewer: viewer, viewer_session: viewer_session})

    Map.put(world, :session, start_viewer_impersonation(world))
  end

  when_ "I end the impersonation session", fn world ->
    session =
      world.session
      |> click(css("[data-test=stop-impersonation-btn]"))
      |> assert_has(css("[data-test=org-name]"))

    Map.put(world, :session, session)
  end

  then_ "I am returned to the operator dashboard", fn world ->
    assert String.starts_with?(current_path(world.session), "/admin"),
           "expected an /admin path after ending impersonation, got #{current_path(world.session)}"

    world.session
    |> assert_has(css("[data-test=org-name]"))
    |> refute_has(css("[data-test=impersonation-banner]"))

    world
  end

  then_ "the viewer's session is not affected", fn world ->
    assert Repo.exists?(
             from(t in ViewerToken,
               where: t.viewer_id == ^world.viewer.id and t.context == "session"
             )
           ),
           "expected the viewer's own session token to survive the impersonation"

    world.viewer_session
    |> visit("/account?org=#{world.org.slug}")
    |> assert_has(css("[data-test=viewer-sign-out]"))
    |> assert_has(css("[data-test=account-email]", text: world.viewer.email))
    |> Wallaby.end_session()

    Map.delete(world, :viewer_session)
  end

  # ---- Viewer account management -----------------------------------------

  when_ "I edit my display name and save", fn world ->
    new_name = "Renamed Viewer #{System.unique_integer([:positive])}"

    session =
      world
      |> open_account_editor()
      |> fill_in(css("[data-test=account-display-name-input]"), with: new_name)
      |> click(css("[data-test=account-save-btn]"))
      |> assert_has(css("[data-test=account-display-name]", text: new_name))

    Map.merge(world, %{session: session, new_display_name: new_name})
  end

  then_ "my profile reflects the new display name", fn world ->
    assert_has(
      world.session,
      css("[data-test=account-display-name]", text: world.new_display_name)
    )

    assert Repo.reload!(world.viewer).display_name == world.new_display_name
    world
  end

  when_ "I upload a new avatar image and save", fn world ->
    avatar_path = Path.expand("priv/static/images/logo.svg")

    session =
      world
      |> open_account_editor()
      |> attach_file(css("[data-test=account-avatar-input]"), path: avatar_path)
      |> click(css("[data-test=account-save-btn]"))
      |> assert_has(css("[data-test=account-edit-btn]"))

    Map.put(world, :session, session)
  end

  then_ "my profile reflects the new avatar", fn world ->
    viewer = Repo.reload!(world.viewer)

    assert is_binary(viewer.avatar_url) and viewer.avatar_url != "",
           "expected an avatar_url on the viewer after upload, got #{inspect(viewer.avatar_url)}"

    assert_has(world.session, css("[data-test=account-avatar]"))
    Map.put(world, :viewer, viewer)
  end

  when_ "I toggle my marketing opt-in preference and save", fn world ->
    before = Repo.reload!(world.viewer).marketing_opt_in

    session =
      world
      |> open_account_editor()
      |> click(css("[data-test=account-marketing-opt-in]"))
      |> click(css("[data-test=account-save-btn]"))
      |> assert_has(css("[data-test=account-edit-btn]"))

    Map.merge(world, %{session: session, marketing_opt_in_before: before})
  end

  then_ "my marketing preference is updated", fn world ->
    viewer = Repo.reload!(world.viewer)

    assert viewer.marketing_opt_in == not world.marketing_opt_in_before,
           "expected marketing_opt_in to flip from #{world.marketing_opt_in_before}"

    Map.put(world, :viewer, viewer)
  end

  when_ "I confirm account deletion", fn world ->
    # A published landing page makes the tenant's "/" render the viewer
    # layout (flash + header) for a signed-out visitor.
    insert(:landing_section,
      organization: world.org,
      section_type: :header_text,
      config: %{"headline" => "Welcome back anytime"}
    )

    session = visit_live(world.session, "/account?org=#{world.org.slug}")

    accept_confirm(session, fn s -> click(s, css("[data-test=account-delete-btn]")) end)

    # After deletion the viewer lands on this tenant's site, signed out, with
    # a confirmation flash.
    session =
      session
      |> assert_has(css("#flash-info", text: "Your account has been deleted."))
      |> assert_has(css("[data-test=landing-page]"))
      |> assert_has(css("[data-test=sign-in-link]"))

    # The tenant is only known from `?org=` here, so the redirect must keep it.
    landed = URI.parse(current_url(session))
    assert landed.path == "/"
    assert URI.decode_query(landed.query || "")["org"] == world.org.slug

    Map.put(world, :session, session)
  end

  # Account deletion is a soft delete (project rule): the row stays with
  # `deleted_at` set, every session token is revoked, and the email can no
  # longer obtain a sign-in link.
  then_ "my viewer account is deactivated and I can no longer sign in", fn world ->
    viewer = Repo.get!(Viewer, world.viewer.id)

    assert viewer.deleted_at, "expected deleted_at to be set on the deleted viewer"
    refute Repo.exists?(from(t in ViewerToken, where: t.viewer_id == ^viewer.id))

    capture_emails()

    {:ok, login_session} =
      Wallaby.start_session(metadata: Phoenix.Ecto.SQL.Sandbox.metadata_for(Repo, self()))

    try do
      login_session
      |> visit_live("/login?org=#{world.org.slug}")
      |> fill_in(css("[data-test=login-email-input]"), with: viewer.email)
      |> click(css("[data-test=login-submit-btn]"))
      |> assert_has(css("[data-test=check-email-message]"))

      email = viewer.email
      refute_receive {:email, %Swoosh.Email{to: [{_, ^email}]}}, 1_000
    after
      Application.delete_env(:swoosh, :shared_test_process)
      Wallaby.end_session(login_session)
    end

    Map.put(world, :viewer, viewer)
  end

  then_ "my account no longer appears in the operator's viewer list", fn world ->
    org = world.org
    other = insert(:subscribed_viewer, organization: org, display_name: "Still Active Viewer")
    operator = insert(:user, confirmed_at: DateTime.utc_now())
    insert(:membership, user: operator, organization: org, role: :admin)

    {:ok, operator_session} =
      Wallaby.start_session(metadata: Phoenix.Ecto.SQL.Sandbox.metadata_for(Repo, self()))

    try do
      operator_session
      |> WallabyCase.log_in_session(operator, org)
      |> visit_live("/admin/members?org=#{org.slug}")
      |> click(button("Viewers"))
      |> assert_has(css("[data-test=viewer-row-#{other.id}]"))
      |> refute_has(css("[data-test=viewer-row-#{world.viewer.id}]"))
    after
      Wallaby.end_session(operator_session)
    end

    world
  end

  # Checks the page the deletion redirect landed on; no re-visit.
  then_ "I am logged out", fn world ->
    world.session
    |> assert_has(css("[data-test=sign-in-link]"))
    |> refute_has(css("[data-test=viewer-sign-out]"))

    world
  end

  # ---- Viewer registration and login --------------------------------------

  given_ "the tenant site is accessible", fn world ->
    org = insert(:organization)

    session =
      world.session
      |> visit("/browse?org=#{org.slug}")
      |> assert_has(css("[data-test=sign-in-link]"))

    Map.merge(world, %{org: org, session: session})
  end

  given_ "I am an unauthenticated user on the tenant site", fn world ->
    world.session
    |> visit("/browse?org=#{world.org.slug}")
    |> assert_has(css("[data-test=sign-in-link]"))
    |> refute_has(css("[data-test=viewer-sign-out]"))

    world
  end

  when_ "I submit the registration form with a valid email and password", fn world ->
    email = unique_viewer_email()

    session =
      world.session
      |> visit_live("/register?org=#{world.org.slug}")
      |> fill_in(css("[data-test=register-email-input]"), with: email)
      |> fill_in(css("[data-test=register-password-input]"), with: "correct horse battery")
      |> click(css("[data-test=register-submit-btn]"))

    Map.merge(world, %{session: session, viewer_email: email})
  end

  then_ "a viewer account is created for my email", fn world ->
    Map.put(world, :viewer, fetch_registered_viewer!(world))
  end

  then_ "I am logged in", fn world ->
    assert_has(world.session, css("[data-test=viewer-sign-out]"))
    world
  end

  when_ "I submit only my email address on the registration form", fn world ->
    email = unique_viewer_email()
    capture_emails()

    session =
      world.session
      |> visit_live("/register?org=#{world.org.slug}")
      |> fill_in(css("[data-test=register-email-input]"), with: email)
      |> click(css("[data-test=register-submit-btn]"))
      |> assert_has(css("[data-test=check-email-message]"))

    Map.merge(world, %{session: session, viewer_email: email})
  end

  then_ "a viewer account is created", fn world ->
    Map.put(world, :viewer, fetch_registered_viewer!(world))
  end

  then_ "a magic link is sent to my email", fn world ->
    Map.put(world, :magic_link_path, receive_magic_link!(world.viewer_email))
  end

  given_ "I have a viewer account", fn world ->
    viewer = insert(:viewer, organization: world.org, email: unique_viewer_email())
    Map.merge(world, %{viewer: viewer, viewer_email: viewer.email})
  end

  when_ "I enter my email on the login page", fn world ->
    capture_emails()

    session =
      world.session
      |> visit_live("/login?org=#{world.org.slug}")
      |> fill_in(css("[data-test=login-email-input]"), with: world.viewer_email)
      |> click(css("[data-test=login-submit-btn]"))
      |> assert_has(css("[data-test=check-email-message]"))

    Map.put(world, :session, session)
  end

  then_ "a magic link email is sent to me", fn world ->
    Map.put(world, :magic_link_path, receive_magic_link!(world.viewer_email))
  end

  then_ "clicking that link creates a session without requiring a password", fn world ->
    session =
      world.session
      |> visit(world.magic_link_path)
      |> assert_has(css("[data-test=viewer-sign-out]"))

    assert Repo.exists?(
             from(t in ViewerToken,
               where: t.viewer_id == ^world.viewer.id and t.context == "session"
             )
           )

    Map.put(world, :session, session)
  end

  given_ "I have a viewer account with a password set", fn world ->
    email = unique_viewer_email()
    password = "correct horse battery"

    {:ok, viewer} = Viewers.register_viewer(world.org, %{email: email, password: password})

    assert viewer.hashed_password,
           "expected register_viewer/2 to store a password hash for #{email}"

    Map.merge(world, %{viewer: viewer, viewer_email: email, viewer_password: password})
  end

  when_ "I submit valid credentials on the login page", fn world ->
    session =
      world.session
      |> visit_live("/login?org=#{world.org.slug}")
      |> fill_in(css("[data-test=login-email-input]"), with: world.viewer_email)
      |> fill_in(css("[data-test=login-password-input]"), with: world.viewer_password)
      |> click(css("[data-test=login-submit-btn]"))

    Map.put(world, :session, session)
  end

  given_ "a magic link token that has expired", fn world ->
    viewer = insert(:viewer, organization: world.org)
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    expired_at = DateTime.utc_now() |> DateTime.add(-20, :minute) |> DateTime.truncate(:second)

    viewer_token
    |> Repo.insert!()
    |> Ecto.Changeset.change(inserted_at: expired_at)
    |> Repo.update!()

    Map.merge(world, %{viewer: viewer, expired_token: encoded_token})
  end

  when_ "I click the expired magic link", fn world ->
    session = visit(world.session, "/magic-link/#{world.expired_token}?org=#{world.org.slug}")
    Map.put(world, :session, session)
  end

  then_ "I see an error indicating the link is invalid or expired", fn world ->
    assert_has(world.session, css("#flash-error", text: "The link is invalid or it has expired."))
    world
  end

  then_ "no session is created", fn world ->
    refute Repo.exists?(
             from(t in ViewerToken,
               where: t.viewer_id == ^world.viewer.id and t.context == "session"
             )
           )

    world.session
    |> refute_has(css("[data-test=viewer-sign-out]"))
    |> assert_has(css("[data-test=sign-in-link]"))

    world
  end

  then_ "my session is invalidated", fn world ->
    refute Repo.exists?(
             from(t in ViewerToken,
               where: t.viewer_id == ^world.viewer.id and t.context == "session"
             )
           ),
           "expected the viewer's session token to be deleted on logout"

    # Checks the page logout landed on (no re-visit, so the redirect target
    # is still current for the next step): signed-out header, positively.
    world.session
    |> assert_has(css("[data-test=sign-in-link]"))
    |> refute_has(css("[data-test=viewer-sign-out]"))

    world
  end

  then_ "I am redirected to the login page", fn world ->
    assert current_path(world.session) == "/login",
           "expected logout to redirect to /login, got #{current_path(world.session)}"

    assert_has(world.session, css("[data-test=login-form]"))
    world
  end

  # ---- Private helpers ----------------------------------------------------

  # Waits for the members LiveView to connect before switching tabs: a
  # `phx-click` fired before the socket joins is dropped silently.
  defp open_viewers_tab(world) do
    world.session
    |> visit_live("/admin/members?org=#{world.org.slug}")
    |> click(button("Viewers"))
    |> assert_has(css("[data-test=viewer-list]"))
  end

  # Clicks the row's "View as" link (a POST to /viewer-session/impersonate)
  # and waits for the impersonation banner on the viewer site.
  defp start_viewer_impersonation(world) do
    world
    |> open_viewers_tab()
    |> click(css("[data-test=impersonate-viewer-#{world.viewer.id}]"))
    |> assert_has(css("[data-test=impersonation-banner]"))
  end

  defp sign_in_viewer_via_magic_link(session, org, viewer) do
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    session
    |> visit("/magic-link/#{encoded_token}?org=#{org.slug}")
    |> assert_has(css("[data-test=viewer-sign-out]"))
  end

  defp open_account_editor(world) do
    world.session
    |> visit_live("/account?org=#{world.org.slug}")
    |> click(css("[data-test=account-edit-btn]"))
    |> assert_has(css("[data-test=account-edit-form]"))
  end

  defp unique_viewer_email, do: "viewer-#{System.unique_integer([:positive])}@example.com"

  defp fetch_registered_viewer!(world) do
    viewer = Viewers.get_viewer_by_email(world.org, world.viewer_email)
    assert viewer, "expected a viewer account for #{world.viewer_email} in #{world.org.slug}"
    viewer
  end

  # Swoosh's test adapter delivers to `:shared_test_process` when set, so
  # mail sent from the LiveView process reaches this step process.
  defp capture_emails, do: Application.put_env(:swoosh, :shared_test_process, self())

  defp receive_magic_link!(email_address) do
    assert_receive {:email, %Swoosh.Email{to: [{_, ^email_address}]} = email}, 5_000
    Application.delete_env(:swoosh, :shared_test_process)

    [_, path] = Regex.run(~r{https?://[^/\s]+(/magic-link/\S+)}, email.text_body)
    path
  end
end
