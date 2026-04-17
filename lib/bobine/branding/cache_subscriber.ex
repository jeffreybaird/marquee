defmodule Bobine.Branding.CacheSubscriber do
  @moduledoc """
  Listens for theme lifecycle events and drops the cached theme for the
  affected organization so every node serves the new CSS variables on
  the next request.

  Theme events broadcast from `Bobine.Branding` land on the platform
  topic (themes carry `organization_id` but no preloaded `:organization`
  association, so `Bobine.Events.broadcast/2` routes them as platform
  events). Subscribing globally is sufficient and mirrors the
  `HeroCacheSubscriber` pattern.
  """

  use GenServer

  alias Bobine.Cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Bobine.Events.subscribe_global()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:bobine_event, {:theme_created, theme}, _scope}, state) do
    invalidate(theme)
    {:noreply, state}
  end

  def handle_info({:bobine_event, {:theme_updated, theme}, _scope}, state) do
    invalidate(theme)
    {:noreply, state}
  end

  def handle_info({:bobine_event, {:theme_deleted, theme}, _scope}, state) do
    invalidate(theme)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp invalidate(%{organization_id: org_id}) when not is_nil(org_id) do
    Cache.delete("theme:#{org_id}")
  end

  defp invalidate(_), do: :ok
end
