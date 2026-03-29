defmodule Bobine.MetricsTest do
  use ExUnit.Case, async: true

  test "video_viewed/2 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bobine, :video, :viewed]])

    Bobine.Metrics.video_viewed("org_123", "video_456")

    assert_received {[:bobine, :video, :viewed], ^ref, %{count: 1},
                     %{org_id: "org_123", video_id: "video_456"}}
  end

  test "subscription_created/2 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bobine, :subscription, :created]])

    Bobine.Metrics.subscription_created("org_123", "basic")

    assert_received {[:bobine, :subscription, :created], ^ref, %{count: 1},
                     %{org_id: "org_123", plan: "basic"}}
  end

  test "subscription_canceled/2 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bobine, :subscription, :canceled]])

    Bobine.Metrics.subscription_canceled("org_123", "basic")

    assert_received {[:bobine, :subscription, :canceled], ^ref, %{count: 1},
                     %{org_id: "org_123", plan: "basic"}}
  end

  test "video_upload_initiated/1 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bobine, :video, :upload_initiated]])

    Bobine.Metrics.video_upload_initiated("org_123")

    assert_received {[:bobine, :video, :upload_initiated], ^ref, %{count: 1},
                     %{org_id: "org_123"}}
  end

  test "external_api_call/4 emits telemetry event with duration" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bobine, :external_api, :call]])

    Bobine.Metrics.external_api_call("mux", "create_asset", 150, :ok)

    assert_received {[:bobine, :external_api, :call], ^ref, %{duration: 150},
                     %{service: "mux", operation: "create_asset", status: :ok}}
  end

  test "webhook_delivered/3 emits telemetry event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:bobine, :webhook, :delivered]])

    Bobine.Metrics.webhook_delivered("org_123", "video.created", :success)

    assert_received {[:bobine, :webhook, :delivered], ^ref, %{count: 1},
                     %{org_id: "org_123", event_type: "video.created", status: :success}}
  end
end
