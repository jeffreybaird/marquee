defmodule Marquee.Content.AccessControl do
  @moduledoc """
  Determines whether a viewer can watch a video based on
  the video's visibility setting and the viewer's subscription status.

  `feed_access/2` applies the organization-level Shorts feed access level
  instead: inside the feed, every clip follows the feed's level and each
  video's own visibility is ignored.
  """

  alias Marquee.Viewers.SubscriptionAccess

  @doc """
  Returns true if the viewer can watch the given video.

      iex> can_watch?(%{visibility: "public"}, nil)
      true

      iex> can_watch?(%{visibility: "free_with_account"}, nil)
      false

      iex> can_watch?(%{visibility: "free_with_account"}, %Marquee.Viewers.Viewer{})
      true

      iex> can_watch?(%{visibility: "subscribers_only"}, nil)
      false

      iex> can_watch?(%{visibility: "subscribers_only"}, %Marquee.Viewers.Viewer{subscription_status: "active"})
      true

      iex> can_watch?(%{visibility: "subscribers_only"}, %Marquee.Viewers.Viewer{subscription_status: "none"})
      false
  """
  def can_watch?(video, viewer) do
    case video.visibility do
      "public" ->
        true

      "free_with_account" ->
        not is_nil(viewer)

      "subscribers_only" ->
        viewer != nil && SubscriptionAccess.has_access?(viewer)
    end
  end

  @doc """
  Decides whether a viewer may play clips in a Shorts feed with the given
  access level. Returns `:playable` or `{:locked, reason}` where `reason`
  names the call to action: `:login`, `:subscribe`, `:payment_issue`, or
  `:suspended` (no call to action).

  Past-due viewers count as signed-in but not subscribed: they play in a
  public or free-with-account feed and are asked to fix their payment in a
  subscribers-only feed.

      iex> feed_access("public", nil)
      :playable

      iex> feed_access("free_with_account", nil)
      {:locked, :login}

      iex> feed_access("free_with_account", %Marquee.Viewers.Viewer{subscription_status: "none"})
      :playable

      iex> feed_access("subscribers_only", %Marquee.Viewers.Viewer{subscription_status: "active"})
      :playable

      iex> feed_access("subscribers_only", %Marquee.Viewers.Viewer{subscription_status: "none"})
      {:locked, :subscribe}

      iex> feed_access("subscribers_only", %Marquee.Viewers.Viewer{subscription_status: "past_due"})
      {:locked, :payment_issue}

      iex> feed_access("public", %Marquee.Viewers.Viewer{subscription_status: "active", status: :banned})
      {:locked, :suspended}
  """
  def feed_access(_access_level, %{status: status}) when status in [:suspended, :banned],
    do: {:locked, :suspended}

  def feed_access("public", _viewer), do: :playable
  def feed_access(_access_level, nil), do: {:locked, :login}
  def feed_access("free_with_account", _viewer), do: :playable

  def feed_access("subscribers_only", %{subscription_status: "past_due"}),
    do: {:locked, :payment_issue}

  def feed_access("subscribers_only", viewer) do
    if SubscriptionAccess.has_access?(viewer), do: :playable, else: {:locked, :subscribe}
  end

  def feed_access(_unknown_level, _viewer), do: {:locked, :subscribe}
end
