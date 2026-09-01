defmodule Marquee.Podcasts.LifecycleSubscriber do
  @moduledoc """
  Subscribes to viewer subscription + show access events and dispatches
  `Marquee.Workers.PodcastTokenReconciler` jobs so feed tokens are revoked
  when a subscriber's access to a show changes.

  Listens to the audit mirror topic (every org-scoped event flows
  through it) so the subscriber doesn't need a per-org subscription
  manager.
  """

  use GenServer

  require Logger

  alias Marquee.Workers.PodcastTokenReconciler

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Marquee.Events.subscribe_audit()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:marquee_event, event, _scope}, state) do
    handle_event(event)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_event({:viewer_subscription_created, sub}),
    do: enqueue_viewer(sub.viewer_id, "viewer_subscription_created")

  defp handle_event({:subscription_canceled, viewer, _sub}),
    do: enqueue_viewer(viewer.id, "subscription_canceled")

  defp handle_event({:payment_failed, viewer, _sub}),
    do: enqueue_viewer(viewer.id, "payment_failed")

  defp handle_event({:payment_recovered, viewer, _sub}),
    do: enqueue_viewer(viewer.id, "payment_recovered")

  defp handle_event({:subscription_activated, viewer}),
    do: enqueue_viewer(viewer.id, "subscription_activated")

  defp handle_event({:podcast_show_access_changed, show}),
    do: enqueue_show(show.id, "show_access_changed")

  defp handle_event(_), do: :ok

  defp enqueue_viewer(viewer_id, reason) do
    %{"viewer_id" => viewer_id, "reason" => reason}
    |> PodcastTokenReconciler.new()
    |> Oban.insert()
    |> log_enqueue("viewer", viewer_id, reason)
  end

  defp enqueue_show(show_id, reason) do
    %{"show_id" => show_id, "reason" => reason}
    |> PodcastTokenReconciler.new()
    |> Oban.insert()
    |> log_enqueue("show", show_id, reason)
  end

  defp log_enqueue({:ok, _}, _, _, _), do: :ok

  defp log_enqueue({:error, reason}, kind, id, why) do
    Logger.warning("Failed to enqueue token reconciliation",
      kind: kind,
      target_id: id,
      reason: inspect(reason),
      trigger: why
    )
  end
end
