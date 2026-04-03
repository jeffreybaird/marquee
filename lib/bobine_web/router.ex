defmodule BobineWeb.Router do
  use BobineWeb, :router

  import BobineWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BobineWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug BobineWeb.Plugs.SetRequestContext
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :set_organization do
    plug BobineWeb.Plugs.SetOrganization
  end

  pipeline :require_admin do
    plug BobineWeb.Plugs.RequireRole, minimum_role: :viewer_support
  end

  pipeline :require_super_admin do
    plug BobineWeb.Plugs.RequireSuperAdmin
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:bobine, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BobineWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Operator authentication routes (no org resolution — system-level)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", BobineWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{BobineWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", BobineWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{BobineWeb.UserAuth, :mount_current_scope}] do
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

  scope "/admin", BobineWeb.Admin do
    pipe_through [:browser, :set_organization, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [{BobineWeb.Hooks.AssignScope, :require_authenticated}] do
      live "/", DashboardLive
      live "/content", ContentLive
      live "/collections", CollectionsLive
      live "/tags", TagsLive
      live "/catalog", CatalogLive
      live "/analytics", AnalyticsLive
      live "/branding", BrandingLive
      live "/members", MembersLive
      live "/webhooks", WebhooksLive
      live "/settings", SettingsLive
      live "/settings/billing", BillingLive
      live "/settings/billing/success", PlanSuccessLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Super admin routes — no org resolution, super admin only
  ## ──────────────────────────────────────────────────────────────────────

  scope "/super", BobineWeb do
    pipe_through [:browser, :require_authenticated_user, :require_super_admin]

    post "/organizations/:id/impersonate", ImpersonationController, :start
    delete "/impersonate", ImpersonationController, :stop
  end

  scope "/super", BobineWeb.Super do
    pipe_through [:browser, :require_authenticated_user, :require_super_admin]

    live_session :super_admin,
      on_mount: [
        {BobineWeb.UserAuth, :require_authenticated},
        {BobineWeb.Hooks.RequireSuperAdmin, :require_super_admin}
      ] do
      live "/", DashboardLive
      live "/organizations", OrganizationsLive
      live "/organizations/new", OrganizationNewLive
      live "/organizations/:id", OrganizationShowLive
      live "/organizations/:id/edit", OrganizationEditLive
      live "/users", UsersLive
      live "/plans", PlansLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer auth routes (org resolved, plain controllers)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", BobineWeb.Viewer do
    pipe_through [:browser, :set_organization]

    get "/magic-link/:token", SessionController, :magic_link
    post "/viewer-session", SessionController, :create
    delete "/viewer-session", SessionController, :delete
  end

  ## Viewer impersonation routes (operator must be authenticated)
  scope "/", BobineWeb.Viewer do
    pipe_through [:browser, :set_organization, :require_authenticated_user]

    post "/viewer-session/impersonate", SessionController, :start_impersonation
    delete "/viewer-session/impersonate", SessionController, :stop_impersonation
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer registration and login (org resolved, optional auth)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", BobineWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live_session :viewer_auth,
      on_mount: [
        {BobineWeb.Hooks.AssignScope, :assign_org},
        {BobineWeb.Hooks.AssignViewerScope, :optional_auth}
      ] do
      live "/register", RegisterLive
      live "/login", LoginLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer public pages (org resolved, optional auth)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", BobineWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live_session :viewer_public,
      on_mount: [
        {BobineWeb.Hooks.AssignScope, :assign_org},
        {BobineWeb.Hooks.AssignViewerScope, :optional_auth}
      ] do
      live "/", HomeLive
      live "/browse", BrowseLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer authenticated pages (org resolved, login required)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", BobineWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live_session :viewer_authenticated,
      on_mount: [
        {BobineWeb.Hooks.AssignScope, :assign_org},
        {BobineWeb.Hooks.AssignViewerScope, :require_authenticated}
      ] do
      live "/account", AccountLive
      live "/subscribe", SubscribeLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Viewer subscribed pages (org resolved, login + subscription required)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", BobineWeb.Viewer do
    pipe_through [:browser, :set_organization]

    live_session :viewer_subscribed,
      on_mount: [
        {BobineWeb.Hooks.AssignScope, :assign_org},
        {BobineWeb.Hooks.AssignViewerScope, :require_authenticated},
        {BobineWeb.Hooks.RequireSubscription, :require_subscription}
      ] do
      live "/watch/:id", WatchLive
      live "/watchlist", WatchlistLive
    end
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Health check (no auth, used by Fly.io)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/", BobineWeb do
    pipe_through :api

    get "/health", HealthController, :check
  end

  ## ──────────────────────────────────────────────────────────────────────
  ## Webhook receiver routes (no auth, raw body)
  ## ──────────────────────────────────────────────────────────────────────

  scope "/webhooks", BobineWeb do
    pipe_through :api

    post "/mux", WebhookController, :mux
    post "/stripe", WebhookController, :stripe
  end
end
