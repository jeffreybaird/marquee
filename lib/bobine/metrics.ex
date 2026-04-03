defmodule Bobine.Metrics do
  @moduledoc """
  Custom metrics for Bobine business operations.
  Emits :telemetry events that can be consumed by any metrics backend.
  """

  @doc """
  Records a video view event.

      iex> Bobine.Metrics.video_viewed("org_123", "video_456")
      :ok
  """
  def video_viewed(org_id, video_id) do
    :telemetry.execute(
      [:bobine, :video, :viewed],
      %{count: 1},
      %{org_id: org_id, video_id: video_id}
    )
  end

  @doc """
  Records a subscription created event.

      iex> Bobine.Metrics.subscription_created("org_123", "basic")
      :ok
  """
  def subscription_created(org_id, plan_name) do
    :telemetry.execute(
      [:bobine, :subscription, :created],
      %{count: 1},
      %{org_id: org_id, plan: plan_name}
    )
  end

  @doc """
  Records a subscription canceled event.

      iex> Bobine.Metrics.subscription_canceled("org_123", "basic")
      :ok
  """
  def subscription_canceled(org_id, plan_name) do
    :telemetry.execute(
      [:bobine, :subscription, :canceled],
      %{count: 1},
      %{org_id: org_id, plan: plan_name}
    )
  end

  @doc """
  Records a video upload initiated event.

      iex> Bobine.Metrics.video_upload_initiated("org_123")
      :ok
  """
  def video_upload_initiated(org_id) do
    :telemetry.execute(
      [:bobine, :video, :upload_initiated],
      %{count: 1},
      %{org_id: org_id}
    )
  end

  @doc """
  Records an external API call with duration and status.

      iex> Bobine.Metrics.external_api_call("mux", "create_asset", 150, :ok)
      :ok
  """
  def external_api_call(service, operation, duration_ms, status) do
    :telemetry.execute(
      [:bobine, :external_api, :call],
      %{duration: duration_ms},
      %{service: service, operation: operation, status: status}
    )
  end

  @doc """
  Records a webhook delivery attempt.

      iex> Bobine.Metrics.webhook_delivered("org_123", "video.created", :success)
      :ok
  """
  def webhook_delivered(org_id, event_type, status) do
    :telemetry.execute(
      [:bobine, :webhook, :delivered],
      %{count: 1},
      %{org_id: org_id, event_type: event_type, status: status}
    )
  end

  @doc """
  Records a platform subscription created event.

      iex> Bobine.Metrics.platform_subscription_created("org_123", "small_business_super")
      :ok
  """
  def platform_subscription_created(org_id, plan_slug) do
    :telemetry.execute(
      [:bobine, :platform_subscription, :created],
      %{count: 1},
      %{org_id: org_id, plan: plan_slug}
    )
  end

  @doc """
  Records a platform subscription canceled event.

      iex> Bobine.Metrics.platform_subscription_canceled("org_123")
      :ok
  """
  def platform_subscription_canceled(org_id) do
    :telemetry.execute(
      [:bobine, :platform_subscription, :canceled],
      %{count: 1},
      %{org_id: org_id}
    )
  end

  @doc """
  Records a viewer checkout initiated event.

      iex> Bobine.Metrics.checkout_initiated("org_123", "plan_456")
      :ok
  """
  def checkout_initiated(org_id, plan_id) do
    :telemetry.execute(
      [:bobine, :checkout, :initiated],
      %{count: 1},
      %{org_id: org_id, plan_id: plan_id}
    )
  end

  @doc """
  Records a viewer payment failure event.

      iex> Bobine.Metrics.viewer_payment_failed("org_123", "plan_456")
      :ok
  """
  def viewer_payment_failed(org_id, plan_id) do
    :telemetry.execute(
      [:bobine, :viewer_payment, :failed],
      %{count: 1},
      %{org_id: org_id, plan_id: plan_id}
    )
  end

  @doc """
  Records a platform payment failure event.

      iex> Bobine.Metrics.platform_payment_failed("org_123")
      :ok
  """
  def platform_payment_failed(org_id) do
    :telemetry.execute(
      [:bobine, :platform_payment, :failed],
      %{count: 1},
      %{org_id: org_id}
    )
  end
end
