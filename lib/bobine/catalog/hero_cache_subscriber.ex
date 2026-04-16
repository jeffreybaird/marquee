defmodule Bobine.Catalog.HeroCacheSubscriber do
  @moduledoc """
  Listens for video lifecycle events that affect resolved hero slides and
  invalidates the hero cache for the affected organization so the viewer
  home page picks up the change on the next request.

  Hero slides that reference a video without a Mux playback ID are
  filtered out of `Bobine.Catalog.resolve_hero_slides/1`. When Mux
  finishes processing and `:video_ready` fires, we invalidate the cache
  so those slides resurface.
  """

  use GenServer

  alias Bobine.Catalog

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Bobine.Events.subscribe_global()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:bobine_event, {:video_ready, video}, _scope}, state) do
    Catalog.invalidate_hero_cache_for_org(video.organization_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
