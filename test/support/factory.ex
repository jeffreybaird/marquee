defmodule Marquee.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Marquee.Repo

  # -------------------------------------------------------------------------
  # Accounts
  # -------------------------------------------------------------------------

  def organization_factory do
    %Marquee.Accounts.Organization{
      name: sequence(:org_name, &"Test Org #{&1}"),
      slug: sequence(:org_slug, &"test-org-#{&1}"),
      template: "default",
      # Factory orgs are "established" by default so the new-admin onboarding
      # wizard doesn't intercept unrelated dashboard specs. Onboarding tests
      # opt into a fresh org with `onboarding_completed_at: nil`.
      onboarding_completed_at: ~U[2026-01-01 00:00:00Z]
    }
  end

  def user_factory do
    %Marquee.Accounts.User{
      email: sequence(:email, &"user-#{&1}@example.com"),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      is_super_admin: false
    }
  end

  def super_admin_factory do
    %Marquee.Accounts.User{
      email: sequence(:email, &"super-#{&1}@example.com"),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      is_super_admin: true
    }
  end

  def membership_factory do
    %Marquee.Accounts.Membership{
      user: build(:user),
      organization: build(:organization),
      role: :editor,
      # Factory operators have "already seen" the guided admin tour by default
      # so its auto-launching overlay doesn't hijack unrelated dashboard specs.
      # Tour specs opt into a fresh operator with `admin_tour_completed_at: nil`.
      admin_tour_completed_at: ~U[2026-01-01 00:00:00Z]
    }
  end

  def layout_factory do
    %Marquee.Catalog.Layout{
      organization: build(:organization),
      preset_name: "catalog_cinema",
      default_browse_card_variant: "poster_portrait"
    }
  end

  # -------------------------------------------------------------------------
  # Viewers
  # -------------------------------------------------------------------------

  def viewer_factory do
    %Marquee.Viewers.Viewer{
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
    %Marquee.Content.Video{
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
    %Marquee.Content.Collection{
      organization: build(:organization),
      title: sequence(:collection_title, &"Collection #{&1}"),
      slug: sequence(:collection_slug, &"collection-#{&1}"),
      position: sequence(:collection_position, & &1),
      visible: true
    }
  end

  def collection_item_factory do
    %Marquee.Content.CollectionItem{
      organization: build(:organization),
      collection: build(:collection),
      video: build(:video),
      item_type: :video,
      position: sequence(:collection_item_position, & &1)
    }
  end

  def tag_factory do
    %Marquee.Content.Tag{
      organization: build(:organization),
      name: sequence(:tag_name, &"tag-#{&1}"),
      slug: sequence(:tag_slug, &"tag-#{&1}")
    }
  end

  def video_tag_factory do
    %Marquee.Content.VideoTag{
      organization: build(:organization),
      video: build(:video),
      tag: build(:tag)
    }
  end

  def series_factory do
    %Marquee.Content.Series{
      organization: build(:organization),
      title: sequence(:series_title, &"Test Series #{&1}"),
      slug: sequence(:series_slug, &"test-series-#{&1}"),
      visible: true,
      position: 0
    }
  end

  def season_factory do
    %Marquee.Content.Season{
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
    %Marquee.Content.Episode{
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
    %Marquee.Catalog.Row{
      organization: build(:organization),
      title: sequence(:row_title, &"Row #{&1}"),
      source_type: :curated,
      position: sequence(:row_position, & &1),
      visible: true,
      max_items: 20
    }
  end

  def hero_row_factory do
    %Marquee.Catalog.Row{
      organization: build(:organization),
      title: "Hero",
      source_type: :hero,
      position: 0,
      visible: true,
      max_items: 5
    }
  end

  def hero_slide_factory do
    %Marquee.Catalog.HeroSlide{
      organization: build(:organization),
      row: build(:hero_row),
      video: build(:video),
      position: sequence(:hero_slide_position, & &1)
    }
  end

  def row_item_factory do
    %Marquee.Catalog.RowItem{
      organization: build(:organization),
      row: build(:row),
      video: build(:video),
      position: sequence(:row_item_position, & &1)
    }
  end

  # -------------------------------------------------------------------------
  # Landing page
  # -------------------------------------------------------------------------

  def landing_section_factory do
    %Marquee.LandingPage.LandingSection{
      organization: build(:organization),
      section_type: :header_text,
      position: sequence(:landing_section_position, & &1),
      visible: true,
      config: %{"headline" => "A Section"}
    }
  end

  # -------------------------------------------------------------------------
  # Engagement
  # -------------------------------------------------------------------------

  def queue_item_factory do
    %Marquee.Engagement.QueueItem{
      organization: build(:organization),
      viewer: build(:viewer),
      video: build(:video),
      position: sequence(:queue_position, & &1),
      added_from: "browse",
      added_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def watchlist_item_factory do
    %Marquee.Engagement.WatchlistItem{
      organization: build(:organization),
      user: build(:user),
      video: build(:video),
      auto_remove_on_watch: false
    }
  end

  def favorite_factory do
    %Marquee.Engagement.Favorite{
      organization: build(:organization),
      user: build(:user),
      video: build(:video)
    }
  end

  def watch_history_factory do
    %Marquee.Engagement.WatchHistory{
      organization: build(:organization),
      user: build(:user),
      video: build(:video),
      watched_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def progress_factory do
    %Marquee.Engagement.Progress{
      organization: build(:organization),
      user: build(:user),
      video: build(:video),
      position: 0.0,
      completed: false
    }
  end

  def continue_watching_dismissal_factory do
    %Marquee.Engagement.ContinueWatchingDismissal{
      organization: build(:organization),
      viewer: build(:viewer),
      video: build(:video),
      dismissed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def playback_drop_off_factory do
    %Marquee.Engagement.PlaybackDropOff{
      organization: build(:organization),
      video: build(:video),
      viewer: build(:viewer),
      bucket: 0,
      max_position: 0.0,
      video_duration: 600.0,
      left_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def video_drop_off_bucket_factory do
    %Marquee.Engagement.VideoDropOffBucket{
      organization: build(:organization),
      video: build(:video),
      bucket: 0,
      count: 0
    }
  end

  # -------------------------------------------------------------------------
  # Billing
  # -------------------------------------------------------------------------

  def plan_factory do
    %Marquee.Billing.Plan{
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
    %Marquee.Billing.Subscription{
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
    %Marquee.Billing.Coupon{
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
    %Marquee.Billing.ViewerSubscription{
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
    %Marquee.Billing.PlatformPlan{
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
    %Marquee.Billing.PlatformSubscription{
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
    %Marquee.Branding.Theme{
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
  # Audit
  # -------------------------------------------------------------------------

  def audit_log_factory do
    %Marquee.Audit.Log{
      organization: build(:organization),
      user: build(:user),
      action: sequence(:audit_action, &"resource.action_#{&1}"),
      resource_type: "Video",
      resource_id: Ecto.UUID.generate(),
      changes: %{},
      metadata: %{}
    }
  end

  # -------------------------------------------------------------------------
  # Analytics
  # -------------------------------------------------------------------------

  def analytics_event_factory do
    %Marquee.Analytics.Event{
      organization: build(:organization),
      event_type: "video.play",
      occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def analytics_snapshot_factory do
    %Marquee.Analytics.Snapshot{
      organization: build(:organization),
      period_date: Date.utc_today() |> Date.add(-1),
      metric_type: "daily_subscribers",
      value: Decimal.new("10"),
      metadata: %{}
    }
  end

  # -------------------------------------------------------------------------
  # Notifications
  # -------------------------------------------------------------------------

  def notification_factory do
    %Marquee.Notifications.Notification{
      organization: build(:organization),
      title: sequence(:notification_title, &"Notification #{&1}"),
      body: "This is a notification body.",
      type: :email,
      status: :draft
    }
  end

  # -------------------------------------------------------------------------
  # Streaming
  # -------------------------------------------------------------------------

  def live_event_factory do
    %Marquee.Streaming.LiveEvent{
      organization: build(:organization),
      title: sequence(:live_event_title, &"Live Event #{&1}"),
      slug: sequence(:live_event_slug, &"live-event-#{&1}"),
      scheduled_start_at: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second),
      access_type: "subscribers_only",
      status: "scheduled",
      mux_live_stream_id: sequence(:mux_stream_id, &"stream_#{&1}"),
      mux_live_playback_id: sequence(:mux_live_playback, &"live_playback_#{&1}"),
      mux_rtmp_url: "rtmps://global-live.mux.com:443/app"
    }
  end

  def live_event_ticket_factory do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    event = build(:live_event)

    %Marquee.Streaming.LiveEventTicket{
      organization: event.organization,
      live_event: event,
      viewer: build(:viewer),
      amount_cents: 999,
      access_starts_at: now,
      access_ends_at: DateTime.add(now, 48 * 3600, :second)
    }
  end

  def chat_message_factory do
    %Marquee.Streaming.ChatMessage{
      organization: build(:organization),
      live_event: build(:live_event),
      viewer: build(:viewer),
      content: sequence(:chat_content, &"Hello #{&1}!")
    }
  end

  def live_event_chat_ban_factory do
    %Marquee.Streaming.LiveEventChatBan{
      organization: build(:organization),
      live_event: build(:live_event),
      viewer: build(:viewer),
      banned_by_user: build(:user)
    }
  end

  def live_event_reminder_factory do
    %Marquee.Streaming.LiveEventReminder{
      organization: build(:organization),
      live_event: build(:live_event),
      viewer: build(:viewer)
    }
  end

  # -------------------------------------------------------------------------
  # Podcasts
  # -------------------------------------------------------------------------

  def podcast_show_factory do
    %Marquee.Podcasts.Show{
      organization: build(:organization),
      title: sequence(:show_title, &"Show #{&1}"),
      slug: sequence(:show_slug, &"show-#{&1}"),
      description: "A premium podcast.",
      author: "Author Name",
      owner_name: "Owner",
      owner_email: sequence(:show_owner_email, &"owner-#{&1}@example.com"),
      language: "en-us",
      primary_category: "Technology",
      explicit: false,
      source_type: "direct_upload",
      access_mode: "any_active",
      published: true
    }
  end

  def feed_import_show_factory do
    struct!(
      podcast_show_factory(),
      source_type: "feed_import",
      remote_feed_url: sequence(:remote_feed_url, &"https://example.com/feed-#{&1}.xml")
    )
  end

  def podcast_show_tier_factory do
    show = build(:podcast_show)
    plan = build(:plan, organization: show.organization)

    %Marquee.Podcasts.ShowTier{
      organization: show.organization,
      show: show,
      plan: plan
    }
  end

  def podcast_episode_factory do
    show = build(:podcast_show)

    %Marquee.Podcasts.Episode{
      organization: show.organization,
      show: show,
      guid: sequence(:episode_guid, &"guid-#{&1}"),
      title: sequence(:episode_title, &"Episode #{&1}"),
      description: "Episode description.",
      episode_number: sequence(:episode_number_seq, & &1),
      episode_type: "full",
      publish_date: DateTime.utc_now() |> DateTime.truncate(:second),
      duration_seconds: 1800,
      mux_asset_id: sequence(:episode_mux_asset_id, &"asset_ep_#{&1}"),
      mux_playback_id: sequence(:episode_mux_playback_id, &"playback_ep_#{&1}"),
      mux_status: "ready",
      mp3_byte_size: 25_000_000,
      status: "published"
    }
  end

  def podcast_feed_token_factory do
    show = build(:podcast_show)
    viewer = build(:subscribed_viewer, organization: show.organization)

    %Marquee.Podcasts.FeedToken{
      organization: show.organization,
      show: show,
      viewer: viewer,
      token:
        sequence(
          :feed_token,
          &"tok_#{&1}_#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}"
        ),
      status: "active",
      expires_at: DateTime.utc_now() |> DateTime.add(365, :day) |> DateTime.truncate(:second)
    }
  end

  # -------------------------------------------------------------------------
  # Webhooks
  # -------------------------------------------------------------------------

  def webhook_endpoint_factory do
    %Marquee.Webhooks.Endpoint{
      organization: build(:organization),
      url: sequence(:webhook_url, &"https://example.com/webhooks/#{&1}"),
      secret: sequence(:webhook_secret, &"whsec_#{&1}"),
      events: ["video.published"],
      active: true
    }
  end

  def webhook_delivery_factory do
    %Marquee.Webhooks.Delivery{
      endpoint: build(:webhook_endpoint),
      event_type: "video.published",
      payload: %{"event" => "video.published"},
      response_status: 200,
      attempts: 1
    }
  end
end
