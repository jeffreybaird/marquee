alias Marquee.Repo
alias Marquee.Accounts
alias Marquee.Accounts.{Organization, Membership, User}
alias Marquee.Branding

# ---------------------------------------------------------------------------
# Helper: create or fetch organization + theme
# ---------------------------------------------------------------------------

create_org = fn name, slug ->
  %Organization{}
  |> Organization.changeset(%{name: name, slug: slug, template: "default"})
  |> Repo.insert(on_conflict: :nothing, conflict_target: :slug)

  org = Repo.get_by!(Organization, slug: slug)
  IO.puts("Organization: #{org.name} (slug: #{org.slug})")

  unless Repo.get_by(Marquee.Branding.Theme, organization_id: org.id) do
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

# Seed tenant branding so font injection + accent override can be verified
# end-to-end in dev. Uses the Catalog Cinema preset defaults.
demo_org =
  demo_org
  |> Organization.branding_changeset(%{
    accent_color_base: "oklch(0.72 0.14 68)",
    accent_color_hover: "oklch(0.78 0.14 68)",
    accent_color_active: "oklch(0.66 0.14 68)",
    accent_color_subtle: "oklch(0.28 0.06 68)",
    display_font: "Cormorant Garamond",
    preset_name: "catalog_cinema"
  })
  |> Repo.update!()

IO.puts("  branding: #{demo_org.preset_name} / #{demo_org.display_font}")

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
  case Accounts.get_user_by_email("super@marquee.dev") do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: "super@marquee.dev"})
      user = Repo.update!(User.confirm_changeset(user))
      {:ok, user} = user |> User.admin_changeset(%{is_super_admin: true}) |> Repo.update()
      user

    existing ->
      existing
  end

# ---------------------------------------------------------------------------
# Viewers on Demo Studio
# ---------------------------------------------------------------------------

alias Marquee.Viewers
alias Marquee.Viewers.Viewer

create_viewer = fn email, display_name, subscription_status, status, org ->
  case Viewers.get_viewer_by_email(org, email) do
    nil ->
      {:ok, viewer} =
        Viewers.register_viewer(org, %{
          email: email,
          display_name: display_name
        })

      viewer
      |> Viewer.subscription_changeset(%{subscription_status: subscription_status})
      |> Repo.update!()

      if status != :active do
        viewer
        |> Viewer.status_changeset(%{status: status})
        |> Repo.update!()
      end

      IO.puts("  viewer: #{email} (#{subscription_status}, #{status})")

    _existing ->
      IO.puts("  viewer: #{email} (already exists)")
  end
end

IO.puts("\nCreating viewers for #{demo_org.name}:")
create_viewer.("alice@example.com", "Alice", "active", :active, demo_org)
create_viewer.("bob@example.com", "Bob", "trial", :active, demo_org)
create_viewer.("carol@example.com", "Carol", "none", :active, demo_org)
create_viewer.("dave@example.com", "Dave", "canceled", :active, demo_org)
create_viewer.("eve@example.com", "Eve", "past_due", :active, demo_org)
create_viewer.("frank@example.com", "Frank", "active", :suspended, demo_org)
create_viewer.("grace@example.com", "Grace", "none", :active, demo_org)

IO.puts("\nCreating viewers for #{test_org.name}:")
# Same emails as demo_org to prove isolation
create_viewer.("alice@example.com", "Alice (Test)", "active", :active, test_org)
create_viewer.("bob@example.com", "Bob (Test)", "none", :active, test_org)
create_viewer.("zoe@example.com", "Zoe", "trial", :active, test_org)

# ---------------------------------------------------------------------------
# Platform Plans (the 3x3 grid)
# ---------------------------------------------------------------------------

alias Marquee.Billing.PlatformPlan

platform_plans = [
  %{
    slug: "individual_basic",
    name: "Individual Basic",
    usage_tier: :basic,
    business_tier: :individual,
    amount: 2900,
    max_videos: 50,
    max_monthly_views: 5_000,
    max_team_seats: 1,
    max_webhook_endpoints: 1,
    enabled_features: [],
    position: 0
  },
  %{
    slug: "individual_super",
    name: "Individual Super",
    usage_tier: :super,
    business_tier: :individual,
    amount: 7900,
    max_videos: 500,
    max_monthly_views: 50_000,
    max_team_seats: 1,
    max_webhook_endpoints: 1,
    enabled_features: [],
    position: 1
  },
  %{
    slug: "individual_premium",
    name: "Individual Premium",
    usage_tier: :premium,
    business_tier: :individual,
    amount: 14900,
    max_videos: 2_000,
    max_monthly_views: 200_000,
    max_team_seats: 1,
    max_webhook_endpoints: 1,
    enabled_features: [],
    position: 2,
    highlight: true
  },
  %{
    slug: "small_business_basic",
    name: "Small Business Basic",
    usage_tier: :basic,
    business_tier: :small_business,
    amount: 4900,
    max_videos: 50,
    max_monthly_views: 5_000,
    max_team_seats: 5,
    max_webhook_endpoints: 5,
    enabled_features: ["custom_domain", "advanced_drm", "api_access"],
    position: 3
  },
  %{
    slug: "small_business_super",
    name: "Small Business Super",
    usage_tier: :super,
    business_tier: :small_business,
    amount: 12900,
    max_videos: 500,
    max_monthly_views: 50_000,
    max_team_seats: 5,
    max_webhook_endpoints: 5,
    enabled_features: [
      "custom_domain",
      "advanced_drm",
      "api_access",
      "analytics_export_full"
    ],
    position: 4,
    highlight: true
  },
  %{
    slug: "small_business_premium",
    name: "Small Business Premium",
    usage_tier: :premium,
    business_tier: :small_business,
    amount: 24900,
    max_videos: 2_000,
    max_monthly_views: 200_000,
    max_team_seats: 10,
    max_webhook_endpoints: 5,
    enabled_features: [
      "custom_domain",
      "advanced_drm",
      "api_access",
      "analytics_export_full"
    ],
    position: 5
  },
  %{
    slug: "enterprise_basic",
    name: "Enterprise Basic",
    usage_tier: :basic,
    business_tier: :enterprise,
    amount: 9900,
    max_videos: 200,
    max_monthly_views: 20_000,
    max_team_seats: nil,
    max_webhook_endpoints: nil,
    enabled_features: [
      "custom_domain",
      "advanced_drm",
      "api_access",
      "live_streaming",
      "ai_recommendations",
      "priority_support",
      "custom_email_domain",
      "white_label",
      "analytics_export_full"
    ],
    position: 6
  },
  %{
    slug: "enterprise_super",
    name: "Enterprise Super",
    usage_tier: :super,
    business_tier: :enterprise,
    amount: 24900,
    max_videos: 2_000,
    max_monthly_views: 200_000,
    max_team_seats: nil,
    max_webhook_endpoints: nil,
    enabled_features: [
      "custom_domain",
      "advanced_drm",
      "api_access",
      "live_streaming",
      "ai_recommendations",
      "priority_support",
      "custom_email_domain",
      "white_label",
      "analytics_export_full"
    ],
    position: 7
  },
  %{
    slug: "enterprise_premium",
    name: "Enterprise Premium",
    usage_tier: :premium,
    business_tier: :enterprise,
    amount: 49900,
    max_videos: nil,
    max_monthly_views: nil,
    max_team_seats: nil,
    max_webhook_endpoints: nil,
    enabled_features: [
      "custom_domain",
      "advanced_drm",
      "api_access",
      "live_streaming",
      "ai_recommendations",
      "priority_support",
      "custom_email_domain",
      "white_label",
      "analytics_export_full"
    ],
    position: 8,
    highlight: true
  }
]

IO.puts("\nCreating platform plans:")

for plan_attrs <- platform_plans do
  unless Repo.get_by(PlatformPlan, slug: plan_attrs.slug) do
    %PlatformPlan{}
    |> PlatformPlan.changeset(plan_attrs)
    |> Repo.insert!()

    IO.puts("  #{plan_attrs.name} ($#{plan_attrs.amount / 100}/mo)")
  end
end

IO.puts("\nSuper admin: #{super_admin.email}")

IO.puts("""

Seed data ready.

Tenant admin dashboard:
  Visit http://demo.localhost:4000/users/log-in and request a magic link.
  Emails: owner@demo.localhost | editor@demo.localhost | support@demo.localhost

Viewer login:
  Visit http://demo.localhost:4000/login and request a magic link.
  Emails: alice@example.com | bob@example.com | carol@example.com
  (alice has active subscription, bob has trial, carol has none)

Super admin panel:
  Visit http://localhost:4000/users/log-in and log in as super@marquee.dev.
  Then go to http://localhost:4000/super

Magic links are delivered to http://localhost:4000/dev/mailbox in dev.
""")
