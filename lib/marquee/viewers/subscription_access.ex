defmodule Marquee.Viewers.SubscriptionAccess do
  @moduledoc """
  Determines whether a viewer has active access to gated content
  based on their subscription status.
  """

  alias Marquee.Viewers.Viewer

  @doc """
  Returns true if the viewer has active subscription access.

      iex> has_access?(%Marquee.Viewers.Viewer{subscription_status: "active"})
      true

      iex> has_access?(%Marquee.Viewers.Viewer{subscription_status: "none"})
      false

      iex> has_access?(%Marquee.Viewers.Viewer{subscription_status: "canceled"})
      false

      iex> has_access?(%Marquee.Viewers.Viewer{subscription_status: "expired"})
      false

      iex> has_access?(%Marquee.Viewers.Viewer{subscription_status: "past_due"})
      true
  """
  def has_access?(%Viewer{subscription_status: status} = viewer) do
    case status do
      "active" -> true
      "trial" -> not trial_expired?(viewer)
      "past_due" -> true
      _ -> false
    end
  end

  @doc """
  Returns true if the viewer's trial has expired.

      iex> trial_expired?(%Marquee.Viewers.Viewer{trial_expires_at: nil})
      true

      iex> trial_expired?(%Marquee.Viewers.Viewer{trial_expires_at: ~U[2099-12-31 23:59:59Z]})
      false
  """
  def trial_expired?(%Viewer{trial_expires_at: nil}), do: true

  def trial_expired?(%Viewer{trial_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
