defmodule MarqueeFeatures.Steps.TeamMembership do
  @moduledoc """
  Step definitions for team_membership_management.feature.

  Operators manage their team on the Team tab of /admin/members: list
  members with roles, invite by email with a role, and remove members.
  Invitation emails are captured from Swoosh's test adapter via
  `:shared_test_process`; the invitee accepts in a second Wallaby
  session. A removed member's loss of access is checked by signing
  them in through a second session as well.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser

  alias Marquee.Accounts
  alias Marquee.Accounts.Membership
  alias Marquee.Repo
  alias MarqueeWeb.WallabyCase

  given_ "I am an organization owner", fn world ->
    log_in_team_operator(world, :owner)
  end

  given_ "I am an organization admin", fn world ->
    log_in_team_operator(world, :admin)
  end

  given_ "I am an organization editor", fn world ->
    log_in_team_operator(world, :editor)
  end

  given_ "a member exists in my organization", fn world ->
    member = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: member, organization: world.org, role: :editor)
    Map.merge(world, %{member: member, member_membership: membership})
  end

  # ---- Listing ------------------------------------------------------------

  then_ "I see all members listed with their roles", fn world ->
    session = open_team_tab(world.session, world.org)

    world.org
    |> list_org_memberships()
    |> Enum.each(fn membership ->
      row = "[data-test=team-member-#{membership.id}]"

      session
      |> assert_has(css(row, text: membership.user.email))
      |> assert_has(css(row, text: role_label(membership.role)))
    end)

    Map.put(world, :session, session)
  end

  # ---- Invitations --------------------------------------------------------

  when_ "I invite a user by email with a specified role", fn world ->
    email = "invitee-#{System.unique_integer([:positive])}@example.com"
    Application.put_env(:swoosh, :shared_test_process, self())

    session =
      world.session
      |> open_team_tab(world.org)
      |> fill_in(css("[data-test=invite-email-input]"), with: email)
      |> select_option("[data-test=invite-role-select]", "editor")
      |> click(css("[data-test=invite-submit-btn]"))

    Map.merge(world, %{session: session, invitee_email: email, invitee_role: :editor})
  end

  then_ "an invitation email is sent to that address", fn world ->
    email_address = world.invitee_email

    assert_receive {:email, %Swoosh.Email{to: [{_, ^email_address}]} = email}, 5_000
    Application.delete_env(:swoosh, :shared_test_process)

    body = email.text_body || email.html_body || ""
    [_, path] = Regex.run(~r{https?://[^/\s"]+(/\S*invitation\S*?)(?:["\s]|$)}, body)

    Map.put(world, :invitation_path, path)
  end

  then_ "when the invitation is accepted the user joins with the specified role", fn world ->
    {:ok, invitee_session} = start_second_session()

    invitee_session
    |> visit(world.invitation_path)
    |> await_live_connect()
    |> click(css("[data-test=accept-invitation-btn]"))
    |> assert_has(css("[data-test=org-name]"))
    |> Wallaby.end_session()

    user = Accounts.get_user_by_email(world.invitee_email)
    assert user, "expected a user account for #{world.invitee_email} after accepting"

    membership = Accounts.get_membership(world.org, user)
    assert membership, "expected #{world.invitee_email} to be a member of #{world.org.slug}"
    assert membership.role == world.invitee_role

    world
  end

  # ---- Removal ------------------------------------------------------------

  when_ "I remove that member", fn world ->
    row = "[data-test=team-member-#{world.member_membership.id}]"
    session = open_team_tab(world.session, world.org)

    accept_confirm(session, fn s ->
      click(s, css("[data-test=remove-member-#{world.member_membership.id}]"))
    end)

    # Wait (retrying) for the removed row to leave while the operator's own
    # row is still listed, rather than a one-shot refute.
    session =
      session
      |> assert_has(css("[data-test=team-member-#{world.membership.id}]"))
      |> assert_has(css(row, count: 0))

    Map.put(world, :session, session)
  end

  then_ "their membership is revoked", fn world ->
    assert Accounts.get_membership(world.org, world.member) == nil,
           "expected #{world.member.email} to no longer be a member of #{world.org.slug}"

    world
  end

  then_ "they lose access to the admin dashboard", fn world ->
    {:ok, member_session} = start_second_session()

    # The admin mount hook redirects a non-member away with an access error.
    member_session
    |> WallabyCase.log_in_session(world.member)
    |> visit("/admin?org=#{world.org.slug}")
    |> assert_has(css("#flash-error", text: "You don't have access to this organization."))
    |> refute_has(css("[data-test=org-name]", text: world.org.name))
    |> Wallaby.end_session()

    world
  end

  # ---- Authorization ------------------------------------------------------

  when_ "I attempt to manage team members", fn world ->
    session =
      world.session
      |> visit_live("/admin/members?org=#{world.org.slug}")
      |> click(button("Team"))

    Map.put(world, :session, session)
  end

  then_ "I am denied access", fn world ->
    world.session
    |> assert_has(css("[data-test=team-access-denied]"))
    |> refute_has(css("[data-test=invite-member-form]"))
    |> refute_has(css("[data-test^=remove-member-]"))

    world
  end

  # ---- Private helpers ----------------------------------------------------

  # Signs in an operator with `role`, alongside an owner, admin and editor
  # teammate so the Team tab has several members and roles to list.
  defp log_in_team_operator(world, role) do
    org = insert(:organization)
    user = insert(:user, confirmed_at: DateTime.utc_now())
    membership = insert(:membership, user: user, organization: org, role: role)

    teammates =
      for teammate_role <- [:owner, :admin, :editor], teammate_role != role do
        teammate = insert(:user, confirmed_at: DateTime.utc_now())
        insert(:membership, user: teammate, organization: org, role: teammate_role)
      end

    session = WallabyCase.log_in_session(world.session, user, org)

    Map.merge(world, %{
      session: session,
      operator: user,
      org: org,
      membership: membership,
      teammates: teammates
    })
  end

  defp open_team_tab(session, org) do
    session
    |> visit_live("/admin/members?org=#{org.slug}")
    |> click(button("Team"))
    |> assert_has(css("[data-test=team-member-list]"))
  end

  defp list_org_memberships(org) do
    import Ecto.Query, only: [from: 2]

    from(m in Membership, where: m.organization_id == ^org.id, preload: :user)
    |> Repo.all()
  end

  defp role_label(role), do: role |> Atom.to_string() |> String.capitalize()

  defp start_second_session do
    Wallaby.start_session(metadata: Phoenix.Ecto.SQL.Sandbox.metadata_for(Repo, self()))
  end
end
