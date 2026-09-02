defmodule Marquee.Accounts.AdminNudgeDismissal do
  @moduledoc """
  Records that an operator dismissed a setup nudge on the admin dashboard.

  Scoped per user, per organization, per nudge key. A dismissed nudge stays
  hidden for that operator even while its underlying setup step is still
  incomplete — dismissal is "hide this", not "the step is done".
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "admin_nudge_dismissals" do
    field :nudge_key, :string
    field :dismissed_at, :utc_datetime

    belongs_to :user, Marquee.Accounts.User
    belongs_to :organization, Marquee.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a dashboard nudge dismissal.

      iex> cs = Marquee.Accounts.AdminNudgeDismissal.changeset(
      ...>   %Marquee.Accounts.AdminNudgeDismissal{},
      ...>   %{user_id: "u1", organization_id: "o1", nudge_key: "connect_stripe",
      ...>     dismissed_at: ~U[2026-01-01 00:00:00Z]}
      ...> )
      iex> cs.valid?
      true

      iex> cs = Marquee.Accounts.AdminNudgeDismissal.changeset(
      ...>   %Marquee.Accounts.AdminNudgeDismissal{}, %{nudge_key: "connect_stripe"}
      ...> )
      iex> cs.valid?
      false
  """
  def changeset(dismissal, attrs) do
    dismissal
    |> cast(attrs, [:user_id, :organization_id, :nudge_key, :dismissed_at])
    |> validate_required([:user_id, :organization_id, :nudge_key, :dismissed_at])
    |> unique_constraint([:user_id, :organization_id, :nudge_key],
      name: :admin_nudge_dismissals_user_org_key_unique
    )
  end
end
