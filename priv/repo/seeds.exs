alias Bobine.Repo
alias Bobine.Accounts
alias Bobine.Accounts.{Organization, Membership, User}
alias Bobine.Branding

# ---------------------------------------------------------------------------
# Organization
# ---------------------------------------------------------------------------

%Organization{}
|> Organization.changeset(%{
  name: "Demo Studio",
  slug: "demo",
  template: "default"
})
|> Repo.insert(on_conflict: :nothing, conflict_target: :slug)

org = Repo.get_by!(Organization, slug: "demo")

IO.puts("Organization: #{org.name} (slug: #{org.slug})")

# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------

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

  IO.puts("Created default theme")
end

# ---------------------------------------------------------------------------
# Helper: create or fetch user + membership
# ---------------------------------------------------------------------------

create_user_with_membership = fn email, role ->
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
# Seed users
# ---------------------------------------------------------------------------

IO.puts("Creating users for #{org.name}:")

create_user_with_membership.("owner@demo.localhost", :owner)
create_user_with_membership.("editor@demo.localhost", :editor)
create_user_with_membership.("support@demo.localhost", :viewer_support)

IO.puts("""

Seed data ready. Visit http://demo.localhost:4000/users/log-in and
request a magic link for any of the above emails.
Magic links are delivered to http://localhost:4000/dev/mailbox in dev.
""")
