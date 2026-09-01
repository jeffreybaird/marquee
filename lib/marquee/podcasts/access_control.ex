defmodule Marquee.Podcasts.AccessControl do
  @moduledoc """
  Determines whether a viewer can access a Show based on the show's
  `access_mode` and the viewer's active subscriptions.

  Three modes are supported:

    * `"any_active"` — any active subscription to any of the org's plans
    * `"specific_tiers"` — the viewer's active subscription is to one of the
      plans listed on the Show's `show_tiers` association
    * `"audio_only_plan"` — the viewer holds an active subscription on the
      Show's `audio_only_plan`

  This module is pure: it operates on already-loaded data and does not hit
  the database. Higher-level functions in `Marquee.Podcasts` are responsible
  for fetching active subscriptions before calling `can_access?/3`.
  """

  alias Marquee.Billing.ViewerSubscription
  alias Marquee.Podcasts.Show
  alias Marquee.Viewers.SubscriptionAccess
  alias Marquee.Viewers.Viewer

  @active_statuses ~w(active trialing past_due trial)

  @doc """
  Returns true when the viewer is allowed to access the given show.

  `subscriptions` is the list of the viewer's currently-active
  `ViewerSubscription` records (already loaded). For the `any_active`
  mode the function falls back to `SubscriptionAccess.has_access?/1` so
  that virtual subscription state on the viewer (e.g. trial) is honored
  even when the viewer has no `ViewerSubscription` row yet.

      iex> alias Marquee.Podcasts.{AccessControl, Show}
      iex> alias Marquee.Viewers.Viewer
      iex> show = %Show{access_mode: "any_active"}
      iex> AccessControl.can_access?(show, %Viewer{subscription_status: "active"}, [])
      true

      iex> alias Marquee.Podcasts.{AccessControl, Show}
      iex> alias Marquee.Viewers.Viewer
      iex> show = %Show{access_mode: "any_active"}
      iex> AccessControl.can_access?(show, %Viewer{subscription_status: "none"}, [])
      false

      iex> alias Marquee.Podcasts.{AccessControl, Show}
      iex> AccessControl.can_access?(%Show{access_mode: "any_active"}, nil, [])
      false
  """
  def can_access?(_show, nil, _subscriptions), do: false

  def can_access?(%Show{access_mode: "any_active"}, %Viewer{} = viewer, subscriptions) do
    SubscriptionAccess.has_access?(viewer) or has_any_active_subscription?(subscriptions)
  end

  def can_access?(%Show{access_mode: "specific_tiers"} = show, %Viewer{}, subscriptions) do
    allowed_plan_ids = Enum.map(show.access_plans || [], & &1.id)

    Enum.any?(subscriptions, fn sub ->
      active_subscription?(sub) and sub.plan_id in allowed_plan_ids
    end)
  end

  def can_access?(
        %Show{access_mode: "audio_only_plan", audio_only_plan_id: plan_id},
        %Viewer{},
        subscriptions
      )
      when not is_nil(plan_id) do
    Enum.any?(subscriptions, fn sub ->
      active_subscription?(sub) and sub.plan_id == plan_id
    end)
  end

  def can_access?(_show, _viewer, _subscriptions), do: false

  defp has_any_active_subscription?(subscriptions) do
    Enum.any?(subscriptions, &active_subscription?/1)
  end

  defp active_subscription?(%ViewerSubscription{status: status, deleted_at: nil}) do
    status in @active_statuses
  end

  defp active_subscription?(_), do: false
end
