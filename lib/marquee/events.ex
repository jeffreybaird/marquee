defmodule Marquee.Events do
  @moduledoc """
  Event broadcasting for side effects. Context functions broadcast events;
  subscribers handle audit logging, webhook dispatch, analytics, and
  notifications.

  Topic design:

    * `events:{org_id}` — org-scoped events (video created, subscription
      activated, row updated). Broadcast by `broadcast/2`.
    * `events:global` — platform-level events (organization created, super
      admin granted). Broadcast by `broadcast_platform/2`.
    * `events:audit` — mirror topic that receives every event, used by the
      audit subscriber so a single process can log activity across the
      platform without subscribing to every org.

  Per `.claude/scalability.md`, org-scoped events must NOT fan out to
  `events:global`. Callers that previously relied on `events:global` to
  receive org events should subscribe to `events:{org_id}` or to
  `events:audit` instead.
  """

  alias Marquee.Metrics

  @audit_topic "events:audit"
  @global_topic "events:global"

  @doc """
  Broadcasts an org-scoped event to the organization's topic.

  `scope` is a `%Marquee.Accounts.Scope{}` or `nil`. When no organization can
  be resolved from `scope` or the event payload, the event is treated as
  platform-level and routed through `broadcast_platform/2`.

  `event` is a tuple like `{:video_created, %Video{}}`.
  """
  def broadcast(scope, event) do
    case resolve_org_id(scope, event) do
      :platform ->
        broadcast_platform(scope, event)

      org_id ->
        topic = "events:#{org_id}"
        message = {:marquee_event, event, scope}

        Phoenix.PubSub.broadcast(Marquee.PubSub, topic, message)
        Phoenix.PubSub.broadcast(Marquee.PubSub, @audit_topic, message)

        Metrics.pubsub_broadcast(topic, event_name(event), 2, org_id)
        :ok
    end
  end

  @doc """
  Broadcasts a platform-level event to the global topic.

  Use this for events that are not scoped to a single organization:
  organization creation or deletion, super-admin grants and revocations,
  platform-plan changes.
  """
  def broadcast_platform(scope, event) do
    message = {:marquee_event, event, scope}

    Phoenix.PubSub.broadcast(Marquee.PubSub, @global_topic, message)
    Phoenix.PubSub.broadcast(Marquee.PubSub, @audit_topic, message)

    Metrics.pubsub_broadcast(@global_topic, event_name(event), 2, "global")
    :ok
  end

  @doc """
  Subscribes the calling process to events for a specific organization.
  """
  def subscribe(organization_id) do
    Phoenix.PubSub.subscribe(Marquee.PubSub, "events:#{organization_id}")
  end

  @doc """
  Subscribes the calling process to platform-level events.
  """
  def subscribe_global do
    Phoenix.PubSub.subscribe(Marquee.PubSub, @global_topic)
  end

  @doc """
  Subscribes the calling process to the audit mirror topic, which receives
  every event broadcast through `broadcast/2` or `broadcast_platform/2`.
  Intended for the `AuditSubscriber`; prefer narrower topics for anything
  else.
  """
  def subscribe_audit do
    Phoenix.PubSub.subscribe(Marquee.PubSub, @audit_topic)
  end

  defp event_name({name, _resource}) when is_atom(name), do: Atom.to_string(name)
  defp event_name(other), do: inspect(other)

  defp resolve_org_id(%{organization: %{id: id}}, _event) when not is_nil(id), do: id
  defp resolve_org_id(_scope, {_name, %{organization: %{id: id}}}) when not is_nil(id), do: id
  defp resolve_org_id(_scope, _event), do: :platform
end
