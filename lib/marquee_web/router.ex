defmodule MarqueeWeb.Router do
  use MarqueeWeb, :router

  import MarqueeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MarqueeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug MarqueeWeb.Plugs.SetRequestContext
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :set_organization do
    plug MarqueeWeb.Plugs.SetOrganization
    plug MarqueeWeb.Plugs.TelemetryOrgPlug

    plug MarqueeWeb.Plugs.RateLimit,
      bucket: :tenant_pages,
      limit: 300,
      key: :organization_id
  end

  pipeline :optional_organization do
    plug MarqueeWeb.Plugs.SetOrganization, optional: true
  end

  pipeline :rate_limit_auth do
    plug MarqueeWeb.Plugs.RateLimit, bucket: :auth, limit: 10, key: :ip
  end

  pipeline :rate_limit_webhook_mux do
    plug MarqueeWeb.Plugs.RateLimit, bucket: :webhook_mux, limit: 500, key: :ip
  end

  pipeline :rate_limit_webhook_stripe do
    plug MarqueeWeb.Plugs.RateLimit, bucket: :webhook_stripe, limit: 500, key: :ip
  end

  pipeline :podcast_public do
    plug :accepts, ["xml", "html", "*/*"]
    plug MarqueeWeb.Plugs.RateLimit, bucket: :podcast_public, limit: 600, key: :ip
  end

  pipeline :require_admin do
    plug MarqueeWeb.Plugs.RequireRole, minimum_role: :viewer_support
  end

  pipeline :require_super_admin do
    plug MarqueeWeb.Plugs.RequireSuperAdmin
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:marquee, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MarqueeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/dev", MarqueeWeb do
      pipe_through :browser

      live "/components", Dev.CardShowcaseLive, :index
      live "/bot-stats", Dev.BotStatsLive, :index
    end

    scope "/dev", MarqueeWeb do
      pipe_through [:api, :fetch_session]

      post "/bot-auth", Dev.BotAuthController, :create
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Operator authentication routes (no org resolution — system-level)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", MarqueeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {MarqueeWeb.UserAuth, :require_authenticated},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", MarqueeWeb do
    pipe_through [:browser, :rate_limit_auth]

    live_session :current_user,
      on_mount: [
        {MarqueeWeb.UserAuth, :mount_current_scope},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Admin routes (org resolved, auth required, viewer_support+ role)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/admin", MarqueeWeb.Admin do
    pipe_through [:browser, :set_organization, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [
        {MarqueeWeb.Hooks.AssignScope, :require_authenticated},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/", DashboardLive
      live "/content", ContentLive
      live "/collections", CollectionsLive
      live "/series", SeriesLive
      live "/series/:series_id/seasons/:season_id", SeasonLive
      live "/tags", TagsLive
      live "/catalog", CatalogLive
      live "/podcasts", PodcastsLive
      live "/landing", LandingLive
      live "/analytics", AnalyticsLive
      live "/analytics/videos/:video_id", VideoAnalyticsLive
      live "/analytics/series/:series_id", SeriesAnalyticsLive
      live "/analytics/series/:series_id/seasons/:season_id", SeasonAnalyticsLive
      live "/branding", BrandingLive
      live "/appearance", AppearanceLive
      live "/members", MembersLive
      live "/webhooks", WebhooksLive
      live "/settings", SettingsLive
      live "/settings/billing", BillingLive
      live "/settings/billing/success", PlanSuccessLive
      live "/plans", PlansLive
      live "/coupons", CouponsLive
      live "/audit-log", AuditLogLive
      live "/live-events", LiveEventLive.Index
      live "/live-events/new", LiveEventLive.New
      live "/live-events/:slug", LiveEventLive.Show
      live "/live-events/:slug/edit", LiveEventLive.Edit
    end
  end

  # Stripe Connect return/refresh — controller routes (not LiveView)
  scope "/admin/settings/stripe", MarqueeWeb do
    pipe_through [:browser, :set_organization, :require_authenticated_user, :require_admin]

    get "/return", StripeConnectController, :return
    get "/refresh", StripeConnectController, :refresh
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Super admin routes — no org resolution, super admin only
  ## ──────────────────────────────────────────────────────────────────────

  scope "/super", MarqueeWeb do
    pipe_through [:browser, :require_authenticated_user, :require_super_admin]

    post "/organizations/:id/impersonate", ImpersonationController, :start
    delete "/impersonate", ImpersonationController, :stop
  end

  scope "/super", MarqueeWeb.Super do
    pipe_through [:browser, :require_authenticated_user, :require_super_admin]

    live_session :super_admin,
      on_mount: [
        {MarqueeWeb.UserAuth, :require_authenticated},
        {MarqueeWeb.Hooks.RequireSuperAdmin, :require_super_admin},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/", DashboardLive
      live "/analytics", AnalyticsLive
      live "/organizations", OrganizationsLive
      live "/organizations/new", OrganizationNewLive
      live "/organizations/:id", OrganizationShowLive
      live "/organizations/:id/edit", OrganizationEditLive
      live "/users", UsersLive
      live "/plans", PlansLive
      live "/audit-log", AuditLogLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer auth routes (org resolved, plain controllers)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization, :rate_limit_auth]

    get "/magic-link/:token", SessionController, :magic_link
  end

  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    post "/viewer-session", SessionController, :create
    delete "/viewer-session", SessionController, :delete

    post "/events/:slug/purchase", LiveEventPpvController, :create
  end

  ## Viewer impersonation routes (operator must be authenticated)
  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization, :require_authenticated_user]

    post "/viewer-session/impersonate", SessionController, :start_impersonation
    delete "/viewer-session/impersonate", SessionController, :stop_impersonation
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer registration and login (org resolved, optional auth)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live_session :viewer_auth,
      on_mount: [
        {MarqueeWeb.Hooks.AssignScope, :assign_org},
        {MarqueeWeb.Hooks.AssignViewerScope, :optional_auth},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/register", RegisterLive
      live "/login", LoginLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Home / marketing page (org optional — shows marketing when no org)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :optional_organization]

    live_session :home,
      on_mount: [
        {MarqueeWeb.Hooks.AssignScope, :assign_org},
        {MarqueeWeb.Hooks.AssignViewerScope, :optional_auth},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/", HomeLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer public pages (org resolved, optional auth)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    get "/events", LiveEventController, :index
    get "/events/:slug/calendar.ics", LiveEventController, :calendar_ics

    live_session :viewer_public,
      on_mount: [
        {MarqueeWeb.Hooks.AssignScope, :assign_org},
        {MarqueeWeb.Hooks.AssignViewerScope, :optional_auth},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/browse", BrowseLive
      live "/browse/:source", ViewAllLive
      live "/collections/:slug", CollectionLive
      live "/events/:slug", LiveEventWatchLive
      live "/podcasts", PodcastsLive
      live "/podcasts/:slug", PodcastShowLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer authenticated pages (org resolved, login required)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live_session :viewer_authenticated,
      on_mount: [
        {MarqueeWeb.Hooks.AssignScope, :assign_org},
        {MarqueeWeb.Hooks.AssignViewerScope, :require_authenticated},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/account", AccountLive
      live "/account/payment-issue", PaymentIssueLive
      live "/subscribe", SubscribeLive
      live "/subscribe/success", SubscribeSuccessLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer subscribed pages (org resolved, login + subscription required)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", MarqueeWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live_session :viewer_subscribed,
      on_mount: [
        {MarqueeWeb.Hooks.AssignScope, :assign_org},
        {MarqueeWeb.Hooks.AssignViewerScope, :require_authenticated},
        {MarqueeWeb.Hooks.RequireSubscription, :require_subscription},
        {MarqueeWeb.Hooks.SpanEnrichment, :default}
      ] do
      live "/watch/:id", WatchLive
      live "/series/:slug", WatchLive, :series
      live "/series/:slug/season/:season_number", WatchLive, :series_season
      live "/watchlist", WatchlistLive
      live "/favorites", WatchlistLive
      live "/queue", WatchlistLive
      live "/history", HistoryLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Health check (no auth, used by Fly.io)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", MarqueeWeb do
    pipe_through :api

    get "/health", HealthController, :check
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Webhook receiver routes (no auth, raw body)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/webhooks", MarqueeWeb do
    pipe_through [:api, :rate_limit_webhook_mux]

    post "/mux", WebhookController, :mux
  end

  scope "/webhooks", MarqueeWeb do
    pipe_through [:api, :rate_limit_webhook_stripe]

    post "/stripe", WebhookController, :stripe
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Public, token-gated podcast feed + audio
  ## ──────────────────────────────────────────────────────────────────────

  scope "/podcasts", MarqueeWeb do
    pipe_through [:podcast_public]

    get "/:token/feed.xml", PodcastFeedController, :feed
    get "/:token/episodes/:episode_id/audio.mp3", PodcastFeedController, :episode_audio
  end
end
