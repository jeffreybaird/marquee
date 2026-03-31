defmodule Bobine.Content.AccessControl do
  @moduledoc """
  Determines whether a viewer can watch a video based on
  the video's visibility setting and the viewer's subscription status.
  """

  alias Bobine.Viewers.SubscriptionAccess

  @doc """
  Returns true if the viewer can watch the given video.

      iex> can_watch?(%{visibility: "public"}, nil)
      true

      iex> can_watch?(%{visibility: "free_with_account"}, nil)
      false

      iex> can_watch?(%{visibility: "free_with_account"}, %Bobine.Viewers.Viewer{})
      true

      iex> can_watch?(%{visibility: "subscribers_only"}, nil)
      false

      iex> can_watch?(%{visibility: "subscribers_only"}, %Bobine.Viewers.Viewer{subscription_status: "active"})
      true

      iex> can_watch?(%{visibility: "subscribers_only"}, %Bobine.Viewers.Viewer{subscription_status: "none"})
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
end
