defmodule Marquee.Content.ShortFeedCacheSubscriber do
  @moduledoc """
  Drops an organization's cached Shorts viewer feed when it may have
  changed: any short-feed mutation, and any video becoming ready, errored,
  updated, deleted or restored (a video's eligibility or metadata decides
  what the feed shows).

  Subscribes to the `events:audit` mirror topic, which receives every
  org-scoped and platform event, so one process covers every organization.
  Invalidation stays broadcast-based so it keeps working with more nodes.
  """

  use GenServer

  alias Marquee.Content.ShortFeed

  @video_events [:video_ready, :video_errored, :video_updated, :video_deleted, :video_restored]

  @doc """
  Starts the subscriber under its module name.

  Exempt from doctest — starts a process.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Marquee.Events.subscribe_audit()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:marquee_event, {name, resource}, scope}, state) when is_atom(name) do
    if invalidating_event?(name), do: invalidate(org_id_for(resource, scope))
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp invalidating_event?(name),
    do: name in @video_events or String.starts_with?(Atom.to_string(name), "short_feed_")

  defp org_id_for(%{organization_id: org_id}, _scope) when is_binary(org_id), do: org_id
  defp org_id_for(%Marquee.Accounts.Organization{id: org_id}, _scope), do: org_id
  defp org_id_for(_resource, %{organization: %{id: org_id}}), do: org_id
  defp org_id_for(_resource, _scope), do: nil

  defp invalidate(org_id) when is_binary(org_id),
    do: ShortFeed.invalidate_short_feed_cache(org_id)

  defp invalidate(_org_id), do: :ok
end
