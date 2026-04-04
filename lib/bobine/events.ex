defmodule Bobine.Events do
  @moduledoc """
  Event broadcasting for side effects. Context functions broadcast events;
  subscribers handle audit logging, webhook dispatch, analytics, and
  notifications.
  """

  alias Bobine.Metrics

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

    message = {:bobine_event, event, scope}
    org_topic = "events:#{org_id}"

    Phoenix.PubSub.broadcast(Bobine.PubSub, org_topic, message)

    broadcast_count =
      if org_topic == "events:global" do
        1
      else
        Phoenix.PubSub.broadcast(Bobine.PubSub, "events:global", message)
        2
      end

    Metrics.pubsub_broadcast(org_topic, event_name(event), broadcast_count, org_id)
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

  defp event_name({name, _resource}) when is_atom(name), do: Atom.to_string(name)
  defp event_name(other), do: inspect(other)
end
