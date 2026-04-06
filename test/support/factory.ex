defmodule Bobine.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Bobine.Repo

  # -------------------------------------------------------------------------
  # Accounts
  # -------------------------------------------------------------------------

  def organization_factory do
    %Bobine.Accounts.Organization{
      name: sequence(:org_name, &"Test Org #{&1}"),
      slug: sequence(:org_slug, &"test-org-#{&1}"),
      template: "default"
    }
  end

  def user_factory do
    %Bobine.Accounts.User{
      email: sequence(:email, &"user-#{&1}@example.com"),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      is_super_admin: false
    }
  end

  def super_admin_factory do
    %Bobine.Accounts.User{
      email: sequence(:email, &"super-#{&1}@example.com"),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      is_super_admin: true
    }
  end

  def membership_factory do
    %Bobine.Accounts.Membership{
      user: build(:user),
      organization: build(:organization),
      role: :editor
    }
  end

  # -------------------------------------------------------------------------
  # Viewers
  # -------------------------------------------------------------------------

  def viewer_factory do
    %Bobine.Viewers.Viewer{
      organization: build(:organization),
      email: sequence(:viewer_email, &"viewer-#{&1}@example.com"),
      display_name: sequence(:viewer_name, &"Viewer #{&1}"),
      status: :active,
      subscription_status: "none",
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def subscribed_viewer_factory do
    struct!(
      viewer_factory(),
      subscription_status: "active"
    )
  end

  # -------------------------------------------------------------------------
  # Content
  # -------------------------------------------------------------------------

  def video_factory do
    %Bobine.Content.Video{
      organization: build(:organization),
      title: sequence(:video_title, &"Video #{&1}"),
      slug: sequence(:video_slug, &"video-#{&1}"),
      mux_asset_id: sequence(:mux_asset_id, &"asset_#{&1}"),
      mux_playback_id: sequence(:mux_playback_id, &"playback_#{&1}"),
      mux_status: "ready",
      published: false
    }
  end

  def collection_factory do
    %Bobine.Content.Collection{
      organization: build(:organization),
      title: sequence(:collection_title, &"Collection #{&1}"),
      slug: sequence(:collection_slug, &"collection-#{&1}"),
      position: sequence(:collection_position, & &1),
      visible: true
    }
  end

  def collection_item_factory do
    %Bobine.Content.CollectionItem{
      organization: build(:organization),
      collection: build(:collection),
      video: build(:video),
      item_type: :video,
      position: sequence(:collection_item_position, & &1)
    }
  end

  def tag_factory do
    %Bobine.Content.Tag{
      organization: build(:organization),
      name: sequence(:tag_name, &"tag-#{&1}"),
      slug: sequence(:tag_slug, &"tag-#{&1}")
    }
  end

  def video_tag_factory do
    %Bobine.Content.VideoTag{
      organization: build(:organization),
      video: build(:video),
      tag: build(:tag)
    }
  end

  def series_factory do
    %Bobine.Content.Series{
      organization: build(:organization),
      title: sequence(:series_title, &"Test Series #{&1}"),
      slug: sequence(:series_slug, &"test-series-#{&1}"),
      visible: true,
      position: 0
    }
  end

  def season_factory do
    %Bobine.Content.Season{
      organization: build(:organization),
      series: build(:series),
      title: sequence(:season_title, &"Season #{&1}"),
      slug: sequence(:season_slug, &"season-#{&1}"),
      season_number: sequence(:season_number, & &1),
      episode_count: 0,
      visible: true
    }
  end

  def episode_factory do
    %Bobine.Content.Episode{
      organization: build(:organization),
      season: build(:season),
      video: build(:video),
      episode_number: sequence(:episode_number, & &1)
    }
  end

  # -------------------------------------------------------------------------
  # Catalog
  # -------------------------------------------------------------------------

  def row_factory do
    %Bobine.Catalog.Row{
      organization: build(:organization),
      title: sequence(:row_title, &"Row #{&1}"),
      source_type: :curated,
      position: sequence(:row_position, & &1),
      visible: true,
      max_items: 20
    }
  end

  def hero_row_factory do
    %Bobine.Catalog.Row{
      organization: build(:organization),
      title: "Hero",
      source_type: :hero,
      position: 0,
      visible: true,
      max_items: 5
    }
  end

  def hero_slide_factory do
    %Bobine.Catalog.HeroSlide{
      organization: build(:organization),
      row: build(:hero_row),
      video: build(:video),
      position: sequence(:hero_slide_position, & &1)
    }
  end

  def row_item_factory do
    %Bobine.Catalog.RowItem{
      organization: build(:organization),
      row: build(:row),
      video: build(:video),
      position: sequence(:row_item_position, & &1)
    }
  end

  # -------------------------------------------------------------------------
  # Engagement
  # -------------------------------------------------------------------------

  def queue_item_factory do
    %Bobine.Engagement.QueueItem{
      organization: build(:organization),
      viewer: build(:viewer),
      video: build(:video),
      position: sequence(:queue_position, & &1),
      added_from: "browse",
      added_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def watchlist_item_factory do
    %Bobine.Engagement.WatchlistItem{
      organization: build(:organization),
      user: build(:user),
      video: build(:video),
      auto_remove_on_watch: false
    }
  end

  def favorite_factory do
    %Bobine.Engagement.Favorite{
      organization: build(:organization),
      user: build(:user),
      video: build(:video)
    }
  end

  def watch_history_factory do
    %Bobine.Engagement.WatchHistory{
      organization: build(:organization),
      user: build(:user),
      video: build(:video),
      watched_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def progress_factory do
    %Bobine.Engagement.Progress{
      organization: build(:organization),
      user: build(:user),
      video: build(:video),
      position: 0.0,
      completed: false
    }
  end

  # -------------------------------------------------------------------------
  # Billing
  # -------------------------------------------------------------------------

  def plan_factory do
    %Bobine.Billing.Plan{
      organization: build(:organization),
      name: sequence(:plan_name, &"Plan #{&1}"),
      stripe_price_id: sequence(:stripe_price_id, &"price_#{&1}"),
      stripe_product_id: sequence(:stripe_product_id, &"prod_#{&1}"),
      amount: 999,
      interval: :monthly,
      active: true
    }
  end

  def subscription_factory do
    %Bobine.Billing.Subscription{
      organization: build(:organization),
      user: build(:user),
      plan: build(:plan),
      stripe_subscription_id: sequence(:stripe_sub_id, &"sub_#{&1}"),
      status: :active,
      current_period_end:
        DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
    }
  end

  def coupon_factory do
    %Bobine.Billing.Coupon{
      organization: build(:organization),
      code: sequence(:coupon_code, &"CODE#{&1}"),
      name: sequence(:coupon_name, &"Coupon #{&1}"),
      percent_off: Decimal.new("10"),
      duration: :once,
      stripe_coupon_id: sequence(:stripe_coupon_id, &"coupon_#{&1}"),
      stripe_promotion_code_id: sequence(:stripe_promo_id, &"promo_#{&1}"),
      active: true
    }
  end

  def viewer_subscription_factory do
    %Bobine.Billing.ViewerSubscription{
      organization: build(:organization),
      viewer: build(:viewer),
      stripe_subscription_id: sequence(:viewer_sub_id, &"sub_viewer_#{&1}"),
      stripe_customer_id: sequence(:viewer_cus_id, &"cus_viewer_#{&1}"),
      status: "active",
      current_period_end:
        DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
    }
  end

  def platform_plan_factory do
    %Bobine.Billing.PlatformPlan{
      name: sequence(:platform_plan_name, &"Platform Plan #{&1}"),
      slug: sequence(:platform_plan_slug, &"platform-plan-#{&1}"),
      stripe_price_id: sequence(:platform_price_id, &"price_platform_#{&1}"),
      stripe_product_id: sequence(:platform_product_id, &"prod_platform_#{&1}"),
      amount: 4900,
      currency: "usd",
      interval: :monthly,
      usage_tier: :basic,
      business_tier: :individual,
      max_videos: 50,
      max_monthly_views: 5_000,
      max_team_seats: 1,
      max_webhook_endpoints: 1,
      enabled_features: [],
      transaction_fee_percent: 5.0,
      active: true
    }
  end

  def platform_subscription_factory do
    %Bobine.Billing.PlatformSubscription{
      organization: build(:organization),
      platform_plan: build(:platform_plan),
      stripe_subscription_id: sequence(:platform_sub_id, &"sub_platform_#{&1}"),
      stripe_customer_id: sequence(:platform_cus_id, &"cus_platform_#{&1}"),
      status: :active,
      current_period_end:
        DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
    }
  end

  # -------------------------------------------------------------------------
  # Branding
  # -------------------------------------------------------------------------

  def theme_factory do
    %Bobine.Branding.Theme{
      organization: build(:organization),
      brand_primary: "#1a73e8",
      brand_secondary: "#174ea6",
      background: "#0f0f0f",
      surface: "#1c1c1c",
      elevated: "#252525",
      text_primary: "#ffffff",
      text_secondary: "#aaaaaa",
      text_on_accent: "#ffffff",
      accent: "#e8a21a",
      brand_primary_hover: "#2186fc",
      font_heading: "Inter",
      font_body: "Inter",
      border_radius: "0.5rem",
      card_border_radius: "0.75rem",
      border_color: "rgba(255, 255, 255, 0.08)",
      divider_color: "rgba(255, 255, 255, 0.05)",
      nav_background: "rgba(0, 0, 0, 0.85)",
      card_background: "#1c1c1c",
      overlay_color: "rgba(0, 0, 0, 0.7)"
    }
  end

  # -------------------------------------------------------------------------
  # Analytics
  # -------------------------------------------------------------------------

  def analytics_event_factory do
    %Bobine.Analytics.Event{
      organization: build(:organization),
      event_type: "video.play",
      occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  # -------------------------------------------------------------------------
  # Notifications
  # -------------------------------------------------------------------------

  def notification_factory do
    %Bobine.Notifications.Notification{
      organization: build(:organization),
      title: sequence(:notification_title, &"Notification #{&1}"),
      body: "This is a notification body.",
      type: :email,
      status: :draft
    }
  end

  # -------------------------------------------------------------------------
  # Webhooks
  # -------------------------------------------------------------------------

  def webhook_endpoint_factory do
    %Bobine.Webhooks.Endpoint{
      organization: build(:organization),
      url: sequence(:webhook_url, &"https://example.com/webhooks/#{&1}"),
      secret: sequence(:webhook_secret, &"whsec_#{&1}"),
      events: ["video.published"],
      active: true
    }
  end

  def webhook_delivery_factory do
    %Bobine.Webhooks.Delivery{
      endpoint: build(:webhook_endpoint),
      event_type: "video.published",
      payload: %{"event" => "video.published"},
      response_status: 200,
      attempts: 1
    }
  end
end
