defmodule Marquee.TenantDomains.CacheSubscriber do
  @moduledoc "Invalidates cached ready allocations on scoped domain and platform organization events."
  use GenServer

  @doc "Starts the cache event subscriber. Requires the application PubSub process."
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Subscribes to lifecycle events for a cached tenant allocation. Requires the subscriber process."
  def watch(org_id) do
    if Process.whereis(__MODULE__), do: GenServer.call(__MODULE__, {:watch, org_id})
    :ok
  end

  @impl true
  def init(_opts) do
    Marquee.Events.subscribe_global()
    {:ok, MapSet.new()}
  end

  @impl true
  def handle_call({:watch, org_id}, _from, watched) do
    unless MapSet.member?(watched, org_id), do: Marquee.Events.subscribe(org_id)
    {:reply, :ok, MapSet.put(watched, org_id)}
  end

  @impl true
  def handle_info({:marquee_event, {:tenant_domain_updated, domain}, _scope}, state) do
    Marquee.Cache.delete("tenant-domain:#{domain.organization_id}")
    {:noreply, state}
  end

  def handle_info({:marquee_event, {action, org}, _scope}, state)
      when action in [:organization_updated, :organization_deleted] do
    Marquee.Cache.delete("tenant-domain:#{org.id}")
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
