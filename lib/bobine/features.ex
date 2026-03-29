defmodule Bobine.Features do
  @moduledoc """
  Feature flag checks for organizations.
  """

  alias Bobine.Accounts.Organization

  @doc """
  Checks if a feature is enabled for the given organization.

      iex> org = %Bobine.Accounts.Organization{features: %{"live_streaming" => true}}
      iex> Bobine.Features.enabled?(org, :live_streaming)
      true

      iex> org = %Bobine.Accounts.Organization{features: %{}}
      iex> Bobine.Features.enabled?(org, :live_streaming)
      false
  """
  def enabled?(%Organization{features: features}, feature) do
    Map.get(features || %{}, to_string(feature), false)
  end

  @doc """
  Returns all enabled features for an organization.

      iex> org = %Bobine.Accounts.Organization{features: %{"live_streaming" => true, "analytics" => false, "drm" => true}}
      iex> Bobine.Features.list_enabled(org) |> Enum.sort()
      ["drm", "live_streaming"]
  """
  def list_enabled(%Organization{features: features}) do
    (features || %{})
    |> Enum.filter(fn {_k, v} -> v == true end)
    |> Enum.map(fn {k, _v} -> k end)
  end
end
