defmodule Marquee.Features do
  @moduledoc """
  Feature flag checks for organizations.
  """

  alias Marquee.Accounts.Organization

  @known_features ~w(analytics drm live_streaming)

  @doc """
  Returns all known feature flag keys.

      iex> Marquee.Features.known_features()
      ["analytics", "drm", "live_streaming"]
  """
  def known_features, do: @known_features

  @doc """
  Checks if a feature is enabled for the given organization.

      iex> org = %Marquee.Accounts.Organization{features: %{"live_streaming" => true}}
      iex> Marquee.Features.enabled?(org, :live_streaming)
      true

      iex> org = %Marquee.Accounts.Organization{features: %{}}
      iex> Marquee.Features.enabled?(org, :live_streaming)
      false
  """
  def enabled?(%Organization{features: features}, feature) do
    Map.get(features || %{}, to_string(feature), false)
  end

  @doc """
  Returns all enabled features for an organization.

      iex> org = %Marquee.Accounts.Organization{features: %{"live_streaming" => true, "analytics" => false, "drm" => true}}
      iex> Marquee.Features.list_enabled(org) |> Enum.sort()
      ["drm", "live_streaming"]
  """
  def list_enabled(%Organization{features: features}) do
    (features || %{})
    |> Enum.filter(fn {_k, v} -> v == true end)
    |> Enum.map(fn {k, _v} -> k end)
  end
end
