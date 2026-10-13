defmodule Marquee.Analytics.CacheSubscriber do
  @moduledoc """
  Drops an organization's cached analytics overview cards
  (`analytics:overview:{org_id}:{period}`) when a billing event changes its
  subscriber count or MRR, so the operator dashboard reflects the change on
  the next render instead of after the cache TTL.

  Billing events broadcast with an organization scope land on that
  organization's `events:{org_id}` topic, which a single long-lived process
  cannot enumerate, so this subscriber listens on the audit mirror topic
  that receives every event. Invalidation is idempotent.
  """

  use GenServer

  alias Marquee.Cache

  @invalidating_events [
    :subscription_created,
    :subscription_deleted,
    :viewer_subscription_created,
    :subscription_activated,
    :subscription_canceled,
    :payment_failed,
    :payment_recovered,
    :plan_updated
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Marquee.Events.subscribe_audit()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:marquee_event, event, scope}, state) when is_tuple(event) do
    if invalidating_event?(event) do
      event
      |> resolve_event_org_id(scope)
      |> invalidate_overview_cache()
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @doc """
  Returns true when the event can change the overview cards' subscriber
  count or MRR.

      iex> Marquee.Analytics.CacheSubscriber.invalidating_event?({:subscription_activated, %{}})
      true

      iex> Marquee.Analytics.CacheSubscriber.invalidating_event?({:video_created, %{}})
      false
  """
  def invalidating_event?(event) when is_tuple(event) and tuple_size(event) > 0,
    do: elem(event, 0) in @invalidating_events

  def invalidating_event?(_event), do: false

  @doc """
  Resolves the organization id for an event: the scope's organization
  first, then the event payload's `organization_id`.

      iex> Marquee.Analytics.CacheSubscriber.resolve_event_org_id(
      ...>   {:subscription_activated, %{}},
      ...>   %{organization: %{id: "org-1"}}
      ...> )
      "org-1"

      iex> Marquee.Analytics.CacheSubscriber.resolve_event_org_id(
      ...>   {:subscription_created, %{organization_id: "org-2"}},
      ...>   nil
      ...> )
      "org-2"

      iex> Marquee.Analytics.CacheSubscriber.resolve_event_org_id({:subscription_created, %{}}, nil)
      nil
  """
  def resolve_event_org_id(_event, %{organization: %{id: org_id}}) when not is_nil(org_id),
    do: org_id

  def resolve_event_org_id(event, _scope) do
    event
    |> Tuple.to_list()
    |> Enum.find_value(&payload_org_id/1)
  end

  defp payload_org_id(%{organization_id: org_id}) when not is_nil(org_id), do: org_id
  defp payload_org_id(_), do: nil

  defp invalidate_overview_cache(nil), do: :ok

  defp invalidate_overview_cache(org_id),
    do: Cache.delete_by_prefix("analytics:overview:#{org_id}:")
end
