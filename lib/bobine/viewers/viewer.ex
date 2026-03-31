defmodule Bobine.Viewers.Viewer do
  @moduledoc """
  Schema for viewer accounts — customers of an organization.

  Viewers are completely separate from the operator `User` schema.
  There is no foreign key between Viewer and User. This provides
  hard data isolation between orgs at the schema level.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "viewers" do
    belongs_to :organization, Bobine.Accounts.Organization

    # Identity — completely separate from User
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string

    # Auth
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime

    # Account state
    field :status, Ecto.Enum, values: [:active, :suspended, :banned], default: :active

    # Subscription gating (Stripe integration in Feature 05)
    field :subscription_status, :string, default: "none"
    field :subscription_expires_at, :utc_datetime
    field :trial_expires_at, :utc_datetime

    # Profile
    field :onboarding_completed, :boolean, default: false
    field :marketing_opt_in, :boolean, default: false
    field :metadata, :map, default: %{}

    # Soft delete
    field :deleted_at, :utc_datetime

    # Virtual field for impersonation tracking
    field :__impersonating__, :boolean, virtual: true, default: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for viewer registration.

  Normalizes email to lowercase, validates format, and optionally hashes password.

  ## Examples

      iex> registration_changeset(%Bobine.Viewers.Viewer{}, %{email: "TEST@Example.COM"})
      %Ecto.Changeset{changes: %{email: "test@example.com"}}
  """
  def registration_changeset(viewer, attrs) do
    viewer
    |> cast(attrs, [:email, :display_name, :password, :marketing_opt_in, :organization_id])
    |> validate_required([:email, :organization_id])
    |> validate_email()
    |> maybe_set_display_name()
    |> maybe_hash_password()
  end

  @doc """
  Changeset for updating a viewer's profile.

  ## Examples

      iex> profile_changeset(%Bobine.Viewers.Viewer{}, %{display_name: "New Name"})
      %Ecto.Changeset{changes: %{display_name: "New Name"}}
  """
  def profile_changeset(viewer, attrs) do
    viewer
    |> cast(attrs, [:display_name, :avatar_url, :marketing_opt_in])
  end

  @doc """
  Changeset for operator-initiated status changes.

  ## Examples

      iex> status_changeset(%Bobine.Viewers.Viewer{}, %{status: :suspended})
      %Ecto.Changeset{changes: %{status: :suspended}}
  """
  def status_changeset(viewer, attrs) do
    viewer
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:active, :suspended, :banned])
  end

  @doc """
  Changeset for subscription status changes.

  ## Examples

      iex> subscription_changeset(%Bobine.Viewers.Viewer{}, %{subscription_status: "active"})
      %Ecto.Changeset{changes: %{subscription_status: "active"}}
  """
  def subscription_changeset(viewer, attrs) do
    viewer
    |> cast(attrs, [:subscription_status, :subscription_expires_at, :trial_expires_at])
    |> validate_required([:subscription_status])
    |> validate_inclusion(:subscription_status, ~w(none trial active past_due canceled expired))
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint([:organization_id, :email])
  end

  defp maybe_set_display_name(changeset) do
    case get_change(changeset, :display_name) do
      nil ->
        case get_change(changeset, :email) do
          nil -> changeset
          email -> put_change(changeset, :display_name, email |> String.split("@") |> hd())
        end

      _ ->
        changeset
    end
  end

  defp maybe_hash_password(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> validate_length(:password, min: 12, max: 72)
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
