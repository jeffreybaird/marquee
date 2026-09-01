defmodule Marquee.MetricsTest do
  use ExUnit.Case, async: true

  test "video_viewed/2 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :video, :viewed]])

    Marquee.Metrics.video_viewed("org_123", "video_456")

    assert_received {[:marquee, :video, :viewed], ^ref, %{count: 1},
                     %{org_id: "org_123", video_id: "video_456"}}
  end

  test "subscription_created/2 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :subscription, :created]])

    Marquee.Metrics.subscription_created("org_123", "basic")

    assert_received {[:marquee, :subscription, :created], ^ref, %{count: 1},
                     %{org_id: "org_123", plan: "basic"}}
  end

  test "subscription_canceled/2 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :subscription, :canceled]])

    Marquee.Metrics.subscription_canceled("org_123", "basic")

    assert_received {[:marquee, :subscription, :canceled], ^ref, %{count: 1},
                     %{org_id: "org_123", plan: "basic"}}
  end

  test "video_upload_initiated/1 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :video, :upload_initiated]])

    Marquee.Metrics.video_upload_initiated("org_123")

    assert_received {[:marquee, :video, :upload_initiated], ^ref, %{count: 1},
                     %{org_id: "org_123"}}
  end

  test "external_api_call/4 emits telemetry event with duration" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :external_api, :call]])

    Marquee.Metrics.external_api_call("mux", "create_asset", 150, :ok)

    assert_received {[:marquee, :external_api, :call], ^ref, %{duration: 150},
                     %{service: "mux", operation: "create_asset", status: :ok}}
  end

  test "webhook_delivered/3 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :webhook, :delivered]])

    Marquee.Metrics.webhook_delivered("org_123", "video.created", :success)

    assert_received {[:marquee, :webhook, :delivered], ^ref, %{count: 1},
                     %{org_id: "org_123", event_type: "video.created", status: :success}}
  end

  test "watch_mount/6 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :watch, :mount]])

    Marquee.Metrics.watch_mount("org_123", :connected, :ok, 42, 3, 18)

    assert_received {[:marquee, :watch, :mount], ^ref,
                     %{count: 1, duration: 42, query_count: 3, db_duration: 18},
                     %{org_id: "org_123", phase: :connected, status: :ok}}
  end

  test "watch_event/2 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :watch, :event]])

    Marquee.Metrics.watch_event("org_123", "playback_progress")

    assert_received {[:marquee, :watch, :event], ^ref, %{count: 1},
                     %{org_id: "org_123", event: "playback_progress"}}
  end

  test "pubsub_broadcast/4 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:marquee, :pubsub, :broadcast]])

    Marquee.Metrics.pubsub_broadcast("events:org_123", "video_ready", 2, "org_123")

    assert_received {[:marquee, :pubsub, :broadcast], ^ref, %{count: 2},
                     %{org_id: "org_123", topic: "events:org_123", event: "video_ready"}}
  end
end
