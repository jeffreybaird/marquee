defmodule Marquee.Branding.CacheSubscriber do
  @moduledoc """
  Listens for theme lifecycle events and drops the cached theme for the
  affected organization so every node serves the new CSS variables on
  the next request.

  Theme events broadcast with an organization scope land on that
  organization's `events:{org_id}` topic, which a single long-lived process
  cannot enumerate, so the subscriber listens on the audit mirror topic that
  receives every event. It also keeps the platform topic subscription for
  legacy scope-less broadcasts; invalidation is idempotent, so an event seen
  on both topics is harmless.
  """

  use GenServer

  alias Marquee.Cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Marquee.Events.subscribe_audit()
    Marquee.Events.subscribe_global()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:marquee_event, {:theme_created, theme}, _scope}, state) do
    invalidate(theme)
    {:noreply, state}
  end

  def handle_info({:marquee_event, {:theme_updated, theme}, _scope}, state) do
    invalidate(theme)
    {:noreply, state}
  end

  def handle_info({:marquee_event, {:theme_deleted, theme}, _scope}, state) do
    invalidate(theme)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp invalidate(%{organization_id: org_id}) when not is_nil(org_id) do
    Cache.delete("theme:#{org_id}")
  end

  defp invalidate(_), do: :ok
end
