defmodule Marquee.Metrics do
  @moduledoc """
  Custom metrics for Marquee business operations.
  Emits :telemetry events that can be consumed by any metrics backend.
  """

  @doc """
  Records a video view event.

      iex> Marquee.Metrics.video_viewed("org_123", "video_456")
      :ok
  """
  def video_viewed(org_id, video_id) do
    :telemetry.execute(
      [:marquee, :video, :viewed],
      %{count: 1},
      %{org_id: org_id, video_id: video_id}
    )
  end

  @doc """
  Records a subscription created event.

      iex> Marquee.Metrics.subscription_created("org_123", "basic")
      :ok
  """
  def subscription_created(org_id, plan_name) do
    :telemetry.execute(
      [:marquee, :subscription, :created],
      %{count: 1},
      %{org_id: org_id, plan: plan_name}
    )
  end

  @doc """
  Records a subscription canceled event.

      iex> Marquee.Metrics.subscription_canceled("org_123", "basic")
      :ok
  """
  def subscription_canceled(org_id, plan_name) do
    :telemetry.execute(
      [:marquee, :subscription, :canceled],
      %{count: 1},
      %{org_id: org_id, plan: plan_name}
    )
  end

  @doc """
  Records a video upload initiated event.

      iex> Marquee.Metrics.video_upload_initiated("org_123")
      :ok
  """
  def video_upload_initiated(org_id) do
    :telemetry.execute(
      [:marquee, :video, :upload_initiated],
      %{count: 1},
      %{org_id: org_id}
    )
  end

  @doc """
  Records an external API call with duration and status.

      iex> Marquee.Metrics.external_api_call("mux", "create_asset", 150, :ok)
      :ok
  """
  def external_api_call(service, operation, duration_ms, status) do
    :telemetry.execute(
      [:marquee, :external_api, :call],
      %{duration: duration_ms},
      %{service: service, operation: operation, status: status}
    )
  end

  @doc """
  Records a webhook delivery attempt.

      iex> Marquee.Metrics.webhook_delivered("org_123", "video.created", :success)
      :ok
  """
  def webhook_delivered(org_id, event_type, status) do
    :telemetry.execute(
      [:marquee, :webhook, :delivered],
      %{count: 1},
      %{org_id: org_id, event_type: event_type, status: status}
    )
  end

  @doc """
  Records a platform subscription created event.

      iex> Marquee.Metrics.platform_subscription_created("org_123", "small_business_super")
      :ok
  """
  def platform_subscription_created(org_id, plan_slug) do
    :telemetry.execute(
      [:marquee, :platform_subscription, :created],
      %{count: 1},
      %{org_id: org_id, plan: plan_slug}
    )
  end

  @doc """
  Records a platform subscription canceled event.

      iex> Marquee.Metrics.platform_subscription_canceled("org_123")
      :ok
  """
  def platform_subscription_canceled(org_id) do
    :telemetry.execute(
      [:marquee, :platform_subscription, :canceled],
      %{count: 1},
      %{org_id: org_id}
    )
  end

  @doc """
  Records a viewer checkout initiated event.

      iex> Marquee.Metrics.checkout_initiated("org_123", "plan_456")
      :ok
  """
  def checkout_initiated(org_id, plan_id) do
    :telemetry.execute(
      [:marquee, :checkout, :initiated],
      %{count: 1},
      %{org_id: org_id, plan_id: plan_id}
    )
  end

  @doc """
  Records a viewer payment failure event.

      iex> Marquee.Metrics.viewer_payment_failed("org_123", "plan_456")
      :ok
  """
  def viewer_payment_failed(org_id, plan_id) do
    :telemetry.execute(
      [:marquee, :viewer_payment, :failed],
      %{count: 1},
      %{org_id: org_id, plan_id: plan_id}
    )
  end

  @doc """
  Records a platform payment failure event.

      iex> Marquee.Metrics.platform_payment_failed("org_123")
      :ok
  """
  def platform_payment_failed(org_id) do
    :telemetry.execute(
      [:marquee, :platform_payment, :failed],
      %{count: 1},
      %{org_id: org_id}
    )
  end

  @doc """
  Records a video completed event.

      iex> Marquee.Metrics.video_completed("org_123", "video_456")
      :ok
  """
  def video_completed(org_id, video_id) do
    :telemetry.execute(
      [:marquee, :video, :completed],
      %{count: 1},
      %{org_id: org_id, video_id: video_id}
    )
  end

  @doc """
  Records a playback drop-off event.

      iex> Marquee.Metrics.drop_off_recorded("org_123", "video_456")
      :ok
  """
  def drop_off_recorded(org_id, video_id) do
    :telemetry.execute(
      [:marquee, :playback, :drop_off_recorded],
      %{count: 1},
      %{org_id: org_id, video_id: video_id}
    )
  end

  @doc """
  Records a queue item added event.

      iex> Marquee.Metrics.queue_item_added("org_123")
      :ok
  """
  def queue_item_added(org_id) do
    :telemetry.execute(
      [:marquee, :queue, :item_added],
      %{count: 1},
      %{org_id: org_id}
    )
  end

  @doc """
  Records a watch page mount/bootstrap event.

      iex> Marquee.Metrics.watch_mount("org_123", :connected, :ok, 42, 3, 18)
      :ok
  """
  def watch_mount(org_id, phase, status, duration_ms, query_count, db_duration_ms) do
    :telemetry.execute(
      [:marquee, :watch, :mount],
      %{
        count: 1,
        duration: duration_ms,
        query_count: query_count,
        db_duration: db_duration_ms
      },
      %{org_id: org_id, phase: phase, status: status}
    )
  end

  @doc """
  Records a watch-page playback or interaction event handled by the server.

      iex> Marquee.Metrics.watch_event("org_123", "playback_progress")
      :ok
  """
  def watch_event(org_id, event_name) do
    :telemetry.execute(
      [:marquee, :watch, :event],
      %{count: 1},
      %{org_id: org_id, event: event_name}
    )
  end

  @doc """
  Records PubSub broadcast fanout volume.

      iex> Marquee.Metrics.pubsub_broadcast("events:org_123", "video_ready", 2, "org_123")
      :ok
  """
  def pubsub_broadcast(topic, event_name, broadcast_count, org_id \\ nil) do
    :telemetry.execute(
      [:marquee, :pubsub, :broadcast],
      %{count: broadcast_count},
      %{org_id: org_id, topic: topic, event: event_name}
    )
  end

  @doc """
  Records a live event status transition.

      iex> Marquee.Metrics.live_event_transitioned("org_123", "live")
      :ok
  """
  def live_event_transitioned(org_id, to_status) do
    :telemetry.execute(
      [:marquee, :live_event, :transitioned],
      %{count: 1},
      %{org_id: org_id, to_status: to_status}
    )
  end

  @doc """
  Records a chat message sent in a live event.

      iex> Marquee.Metrics.chat_message_sent("org_123")
      :ok
  """
  def chat_message_sent(org_id) do
    :telemetry.execute(
      [:marquee, :live_event, :chat_message_sent],
      %{count: 1},
      %{org_id: org_id}
    )
  end

  @doc """
  Records a PPV ticket created.

      iex> Marquee.Metrics.ppv_ticket_created("org_123")
      :ok
  """
  def ppv_ticket_created(org_id) do
    :telemetry.execute(
      [:marquee, :live_event, :ppv_ticket_created],
      %{count: 1},
      %{org_id: org_id}
    )
  end
end
