defmodule Marquee.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Marquee.Accounts.Scope` carries the current user, their resolved
  organization (tenant), and their membership in that organization. Every
  LiveView and context function receives a scope so that authorization and
  tenant scoping can be enforced consistently.
  """

  alias Marquee.Accounts.{Membership, Organization, User}

  defstruct user: nil, organization: nil, membership: nil

  @doc """
  Creates a scope for the given user. Organization and membership are nil
  until resolved by the SetOrganization plug or AssignScope hook.

      iex> scope = Marquee.Accounts.Scope.for_user(%Marquee.Accounts.User{id: "1", email: "a@b.com"})
      iex> scope.user.email
      "a@b.com"

      iex> Marquee.Accounts.Scope.for_user(nil)
      nil

  """
  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil

  @doc """
  Returns a new scope with the organization and membership set.

      iex> scope = Marquee.Accounts.Scope.for_user(%Marquee.Accounts.User{id: "1", email: "a@b.com"})
      iex> org = %Marquee.Accounts.Organization{id: "2", name: "Acme"}
      iex> membership = %Marquee.Accounts.Membership{id: "3", role: :admin}
      iex> updated = Marquee.Accounts.Scope.with_organization(scope, org, membership)
      iex> updated.organization.name
      "Acme"

      iex> scope2 = Marquee.Accounts.Scope.for_user(%Marquee.Accounts.User{id: "2", email: "b@a.com"})
      iex> org2 = %Marquee.Accounts.Organization{id: "3", name: "Beta"}
      iex> updated2 = Marquee.Accounts.Scope.with_organization(scope2, org2, nil)
      iex> updated2.organization.name
      "Beta"
  """
  def with_organization(%__MODULE__{} = scope, %Organization{} = org, %Membership{} = membership) do
    %{scope | organization: org, membership: membership}
  end

  def with_organization(%__MODULE__{} = scope, %Organization{} = org, nil) do
    %{scope | organization: org, membership: nil}
  end
end
