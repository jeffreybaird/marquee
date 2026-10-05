# Marquee — Project Bootstrap Commands
# Run these in order. Read the comments before each block.

# ============================================================================
# 1. INSTALL / UPDATE THE PHOENIX GENERATOR
# ============================================================================

mix archive.install hex phx_new

# ============================================================================
# 2. CREATE THE PROJECT
# ============================================================================
# Phoenix 1.8 ships with daisyUI + Tailwind, magic link auth, scopes,
# and an AGENTS.md for LLM-assisted dev. We want all of it.

mix phx.new stream_vane

cd stream_vane

# ============================================================================
# 3. INITIAL GIT SETUP
# ============================================================================
# Phoenix 1.8 auto-inits a git repo, but let's make our first commit clean.

git add -A
git commit -m "Initial Phoenix 1.8 scaffold"

# ============================================================================
# 4. ADD YOUR CLAUDE.md AND AGENT FILES
# ============================================================================
# Copy in the CLAUDE.md and .claude/ directory you downloaded.
# Replace the generated AGENTS.md or keep both — CLAUDE.md is for Claude Code,
# AGENTS.md is Phoenix's generic LLM guidelines. They complement each other.

cp ~/Downloads/CLAUDE.md ./CLAUDE.md
cp -r ~/Downloads/.claude ./.claude

git add -A
git commit -m "Add Claude Code agent configuration files"

# ============================================================================
# 5. GENERATE AUTH WITH SCOPES
# ============================================================================
# Phoenix 1.8 scopes are perfect for multi-tenancy. The auth generator creates
# a Scope struct, session management, magic link login, and sudo mode.
#
# This generates: User schema, migration, Scope struct, auth plugs,
# LiveView login/register pages, session controller, email templates via Swoosh.
#
# We use --live so auth pages are LiveView (consistent with the rest of the app).

mix phx.gen.auth Accounts User users --live

# Now run the migration it created:
mix ecto.create
mix ecto.migrate

git add -A
git commit -m "Add user authentication with scopes"

# ============================================================================
# 6. GENERATE CORE SCHEMAS & CONTEXTS
# ============================================================================
# We'll use phx.gen.context for schemas that don't need generated LiveView UI
# (we'll build custom admin UI), and phx.gen.live for a few that benefit from
# the scaffolded CRUD as a starting point.
#
# IMPORTANT: After running phx.gen.auth, the "user" scope is the default.
# The generators will automatically scope resources to the current user.
# We'll customize the scope to include organization_id after generation.

# --- Accounts: Organization & Membership ---
# These are custom — no generator perfectly fits the multi-tenant join table.
# Use phx.gen.schema for the raw schemas, then write the context by hand.

mix phx.gen.schema Accounts.Organization organizations \
  name:string \
  slug:string \
  custom_domain:string \
  stripe_account_id:string \
  template:string

mix phx.gen.schema Accounts.Membership memberships \
  user_id:references:users \
  organization_id:references:organizations \
  role:enum:owner:admin:editor:viewer_support

# --- Content: Video ---
mix phx.gen.context Content Video videos \
  organization_id:references:organizations \
  title:string \
  slug:string \
  description:text \
  mux_asset_id:string \
  mux_playback_id:string \
  mux_upload_id:string \
  mux_status:string \
  duration:float \
  max_resolution:string \
  published:boolean

# --- Content: Collection (series, seasons, categories) ---
mix phx.gen.context Content Collection collections \
  organization_id:references:organizations \
  title:string \
  slug:string \
  description:text \
  type:enum:series:season:category \
  parent_id:references:collections \
  position:integer

# --- Content: Tag ---
mix phx.gen.schema Content.Tag tags \
  organization_id:references:organizations \
  name:string \
  slug:string

mix phx.gen.schema Content.VideoTag video_tags \
  video_id:references:videos \
  tag_id:references:tags

# --- Catalog: Row & Layout ---
mix phx.gen.context Catalog Row rows \
  organization_id:references:organizations \
  title:string \
  source_type:enum:curated:algorithm:filter:personalized \
  filter_config:map \
  position:integer \
  visible:boolean

mix phx.gen.schema Catalog.RowItem row_items \
  row_id:references:rows \
  video_id:references:videos \
  position:integer

# --- Engagement: Watchlist, Favorite, WatchHistory, Progress ---
mix phx.gen.context Engagement WatchlistItem watchlist_items \
  organization_id:references:organizations \
  user_id:references:users \
  video_id:references:videos \
  position:integer \
  auto_remove_on_watch:boolean

mix phx.gen.schema Engagement.Favorite favorites \
  organization_id:references:organizations \
  user_id:references:users \
  video_id:references:videos

mix phx.gen.schema Engagement.WatchHistory watch_histories \
  organization_id:references:organizations \
  user_id:references:users \
  video_id:references:videos \
  watched_at:utc_datetime

mix phx.gen.schema Engagement.Progress progresses \
  organization_id:references:organizations \
  user_id:references:users \
  video_id:references:videos \
  position:float \
  completed:boolean

# --- Billing: Plan & Subscription ---
mix phx.gen.context Billing Plan plans \
  organization_id:references:organizations \
  name:string \
  stripe_price_id:string \
  stripe_product_id:string \
  amount:integer \
  interval:enum:monthly:yearly \
  active:boolean

mix phx.gen.context Billing Subscription subscriptions \
  organization_id:references:organizations \
  user_id:references:users \
  plan_id:references:plans \
  stripe_subscription_id:string \
  status:enum:active:past_due:canceled:trialing \
  current_period_end:utc_datetime

# --- Analytics: Event ---
mix phx.gen.schema Analytics.Event analytics_events \
  organization_id:references:organizations \
  user_id:references:users \
  video_id:references:videos \
  event_type:string \
  metadata:map \
  occurred_at:utc_datetime

# --- Branding: Theme ---
mix phx.gen.context Branding Theme themes \
  organization_id:references:organizations \
  brand_primary:string \
  brand_secondary:string \
  background:string \
  surface:string \
  text_primary:string \
  text_secondary:string \
  accent:string \
  font_heading:string \
  font_body:string \
  border_radius:string \
  card_border_radius:string \
  logo_url:string \
  favicon_url:string

# --- Notifications ---
mix phx.gen.schema Notifications.Notification notifications \
  organization_id:references:organizations \
  title:string \
  body:text \
  type:enum:push:email \
  status:enum:draft:sent \
  sent_at:utc_datetime

# --- Webhooks: Outbound webhook system ---
mix phx.gen.context Webhooks Endpoint webhook_endpoints \
  organization_id:references:organizations \
  url:string \
  secret:string \
  events:array:string \
  active:boolean

mix phx.gen.schema Webhooks.Delivery webhook_deliveries \
  endpoint_id:references:webhook_endpoints \
  event_type:string \
  payload:map \
  response_status:integer \
  response_body:text \
  attempts:integer \
  delivered_at:utc_datetime

# ============================================================================
# 7. RUN ALL MIGRATIONS
# ============================================================================

mix ecto.migrate

git add -A
git commit -m "Add core schemas: org, membership, content, catalog, engagement, billing, branding, analytics, notifications, webhooks"

# ============================================================================
# 8. ADD DEPENDENCIES
# ============================================================================
# Open mix.exs and add these to deps. Then run mix deps.get.
#
# {:oban, "~> 2.18"},
# {:mux, "~> 3.0"},
# {:stripity_stripe, "~> 3.0"},
# {:ex_machina, "~> 2.8", only: :test},
# {:mox, "~> 1.1", only: :test},
# {:gettext, "~> 0.26"},
# {:dns_cluster, "~> 0.1"},
# {:floki, "~> 0.37"},

mix deps.get
mix deps.compile

git add -A
git commit -m "Add Oban, Mux SDK, Stripe, ExMachina, Mox dependencies"

# ============================================================================
# 9. SET UP OBAN
# ============================================================================
# Generate the Oban migrations:

mix ecto.gen.migration add_oban_jobs_table

# Then edit the migration to contain:
#
#   def up do
#     Oban.Migration.up(version: 12)
#   end
#
#   def down do
#     Oban.Migration.down(version: 1)
#   end
#
# Add Oban to your application supervision tree in lib/stream_vane/application.ex:
#
#   {Oban, Application.fetch_env!(:stream_vane, Oban)}
#
# Add Oban config to config/config.exs:
#
#   config :stream_vane, Oban,
#     repo: Marquee.Repo,
#     plugins: [Oban.Plugins.Pruner],
#     queues: [default: 10, webhooks: 5, mux: 5, stripe: 5, analytics: 3]
#
# Add Oban test config to config/test.exs:
#
#   config :stream_vane, Oban, testing: :inline

mix ecto.migrate

git add -A
git commit -m "Configure Oban with job queues"

# ============================================================================
# 10. SET UP TEST INFRASTRUCTURE
# ============================================================================
# Create test support files:
#
# test/support/mocks.ex        — Mox mock definitions
# test/support/factory.ex      — ExMachina factories
#
# Update test/test_helper.exs to include:
#   ExUnit.start()
#   Ecto.Adapters.SQL.Sandbox.mode(Marquee.Repo, :manual)
#
# Update config/test.exs:
#   config :stream_vane, :mux_client, Marquee.Content.MockMuxClient
#   config :stream_vane, :stripe_client, Marquee.Billing.MockStripeClient

git add -A
git commit -m "Set up test infrastructure: factories, mocks"

# ============================================================================
# 11. SET UP TYPESCRIPT
# ============================================================================
# Rename assets/js/app.js to assets/js/app.ts
# Create assets/js/hooks/ directory
# Create assets/js/types/ directory
# Create assets/tsconfig.json
# esbuild already handles .ts files — no config change needed.

mv assets/js/app.js assets/js/app.ts
mkdir -p assets/js/hooks
mkdir -p assets/js/types

# Create a basic tsconfig.json in assets/:
# (see .claude/typescript-hooks.md for the full content)

git add -A
git commit -m "Set up TypeScript with hooks directory structure"

# ============================================================================
# 12. DEPLOYMENT (DigitalOcean via push-button-deploy)
# ============================================================================
# Provision the droplet, managed Postgres, DNS and the deploy workflows with
# the push-button-deploy bootstrap (Postgres backend — the default is sqlite):

DATABASE_BACKEND=postgres ~/src/push-button-deploy/bootstrap.sh .

# This seeds infra/ (Terraform), Dockerfile, deploy/ and
# .github/workflows/{deploy,rollback}.yml, applies the Terraform roots and sets
# the GitHub repo secrets/vars. Every push to main then deploys.
# See .claude/deployment.md for the full process.

git add -A
git commit -m "Add DigitalOcean deployment configuration"

# ============================================================================
# 13. GITHUB ACTIONS CI
# ============================================================================
# Create .github/workflows/ci.yml
# (see .claude/deployment.md for the full workflow)
#
# Then push to GitHub:

git remote add origin git@github.com:jeffreybaird/marquee.git
git push -u origin main

# ============================================================================
# DONE! At this point you have:
# ============================================================================
#
# ✅ Phoenix 1.8 app with LiveView, Tailwind, daisyUI
# ✅ User auth with magic links, scopes, sudo mode
# ✅ All core schemas and migrations
# ✅ Multi-tenant organization + membership tables
# ✅ Content management schemas (videos, collections, tags)
# ✅ Catalog system (rows, row items)
# ✅ Viewer engagement (watchlist, favorites, history, progress)
# ✅ Billing schemas (plans, subscriptions)
# ✅ Branding/theming schemas
# ✅ Analytics event tracking schema
# ✅ Outbound webhook system schemas
# ✅ Oban background job processing
# ✅ Mux + Stripe SDK dependencies
# ✅ Test infrastructure (ExMachina, Mox)
# ✅ TypeScript hooks setup
# ✅ Deployed to DigitalOcean
# ✅ GitHub Actions CI pipeline
#
# NEXT STEPS:
# - Customize the generated Scope to include organization context
# - Build the MuxClientBehaviour and StripeClientBehaviour modules
# - Build the SetOrganization plug for tenant resolution
# - Build the operator dashboard LiveViews
# - Wire up the Mux Player hook
# - Connect Stripe checkout flow