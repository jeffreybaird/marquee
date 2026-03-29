alias Bobine.Repo
alias Bobine.Accounts
alias Bobine.Accounts.{Organization, Membership, User}
alias Bobine.Branding

# ---------------------------------------------------------------------------
# Helper: create or fetch organization + theme
# ---------------------------------------------------------------------------

create_org = fn name, slug ->
  %Organization{}
  |> Organization.changeset(%{name: name, slug: slug, template: "default"})
  |> Repo.insert(on_conflict: :nothing, conflict_target: :slug)

  org = Repo.get_by!(Organization, slug: slug)
  IO.puts("Organization: #{org.name} (slug: #{org.slug})")

  unless Repo.get_by(Bobine.Branding.Theme, organization_id: org.id) do
    {:ok, _theme} =
      Branding.create_theme(%{
        organization_id: org.id,
        background: "#0f0f0f",
        surface: "#1c1c1c",
        text_primary: "#ffffff",
        text_secondary: "#aaaaaa",
        brand_primary: "#1a73e8",
        brand_secondary: "#174ea6",
        accent: "#e8a21a",
        font_heading: "Inter",
        font_body: "Inter",
        border_radius: "0.5rem",
        card_border_radius: "0.75rem"
      })

    IO.puts("  Created default theme")
  end

  org
end

# ---------------------------------------------------------------------------
# Helper: create or fetch user + membership
# ---------------------------------------------------------------------------

create_user_with_membership = fn email, role, org ->
  user =
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, user} = Accounts.register_user(%{email: email})
        Repo.update!(User.confirm_changeset(user))

      existing ->
        existing
    end

  case Accounts.get_membership(org, user) do
    nil ->
      %Membership{}
      |> Membership.changeset(%{user_id: user.id, organization_id: org.id, role: role})
      |> Repo.insert!()

    existing ->
      existing
  end

  IO.puts("  #{role}: #{user.email}")
  user
end

# ---------------------------------------------------------------------------
# Demo Studio org
# ---------------------------------------------------------------------------

demo_org = create_org.("Demo Studio", "demo")

IO.puts("Creating users for #{demo_org.name}:")
create_user_with_membership.("owner@demo.localhost", :owner, demo_org)
create_user_with_membership.("editor@demo.localhost", :editor, demo_org)
create_user_with_membership.("support@demo.localhost", :viewer_support, demo_org)

# ---------------------------------------------------------------------------
# Test Channel org (second org for super admin dashboard to display)
# ---------------------------------------------------------------------------

test_org = create_org.("Test Channel", "test-channel")

IO.puts("Creating users for #{test_org.name}:")
create_user_with_membership.("owner@test-channel.localhost", :owner, test_org)
create_user_with_membership.("editor@test-channel.localhost", :editor, test_org)

# ---------------------------------------------------------------------------
# Super admin user
# ---------------------------------------------------------------------------

super_admin =
  case Accounts.get_user_by_email("super@bobine.dev") do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: "super@bobine.dev"})
      user = Repo.update!(User.confirm_changeset(user))
      {:ok, user} = user |> User.admin_changeset(%{is_super_admin: true}) |> Repo.update()
      user

    existing ->
      existing
  end

IO.puts("\nSuper admin: #{super_admin.email}")

IO.puts("""

Seed data ready.

Tenant admin dashboard:
  Visit http://demo.localhost:4000/users/log-in and request a magic link.
  Emails: owner@demo.localhost | editor@demo.localhost | support@demo.localhost

Super admin panel:
  Visit http://localhost:4000/users/log-in and log in as super@bobine.dev.
  Then go to http://localhost:4000/super

Magic links are delivered to http://localhost:4000/dev/mailbox in dev.
""")
