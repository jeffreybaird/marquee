defmodule Bobine.Events do
  @moduledoc """
  Event broadcasting for side effects. Context functions broadcast events;
  subscribers handle audit logging, webhook dispatch, analytics, and
  notifications.
  """

  @doc """
  Broadcasts an event to org-specific and global PubSub topics.

  scope is a %Scope{} or nil.
  event is a tuple like `{:video_created, %Video{}}`.
  """
  def broadcast(scope, event) do
    org_id =
      case scope do
        %{organization: %{id: id}} -> id
        _ -> "global"
      end

    with {:ok, _} <- ensure_pubsub_running() do
      Phoenix.PubSub.broadcast(
        Bobine.PubSub,
        "events:#{org_id}",
        {:bobine_event, event, scope}
      )

      Phoenix.PubSub.broadcast(
        Bobine.PubSub,
        "events:global",
        {:bobine_event, event, scope}
      )
    end

    :ok
  end

  defp ensure_pubsub_running do
    if Process.whereis(Bobine.PubSub) do
      {:ok, :running}
    else
      require Logger

      Logger.warning("PubSub not running — event broadcast skipped",
        module: __MODULE__
      )

      :skip
    end
  end

  @doc """
  Subscribes the calling process to events for a specific organization.
  """
  def subscribe(organization_id) do
    Phoenix.PubSub.subscribe(Bobine.PubSub, "events:#{organization_id}")
  end

  @doc """
  Subscribes the calling process to all global events.
  """
  def subscribe_global do
    Phoenix.PubSub.subscribe(Bobine.PubSub, "events:global")
  end
end
