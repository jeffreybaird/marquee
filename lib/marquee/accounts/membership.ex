defmodule Marquee.Accounts.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "memberships" do
    field :role, Ecto.Enum, values: [:owner, :admin, :editor, :viewer_support]
    field :admin_tour_completed_at, :utc_datetime

    belongs_to :user, Marquee.Accounts.User
    belongs_to :organization, Marquee.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :user_id, :organization_id])
    |> validate_required([:role, :user_id, :organization_id])
    |> unique_constraint([:user_id, :organization_id])
  end

  @doc """
  Changeset for stamping when this operator finished the guided admin tour.

      iex> cs = Marquee.Accounts.Membership.tour_changeset(
      ...>   %Marquee.Accounts.Membership{},
      ...>   %{admin_tour_completed_at: ~U[2026-09-02 00:00:00Z]}
      ...> )
      iex> Ecto.Changeset.get_change(cs, :admin_tour_completed_at)
      ~U[2026-09-02 00:00:00Z]
  """
  def tour_changeset(membership, attrs) do
    cast(membership, attrs, [:admin_tour_completed_at])
  end
end
