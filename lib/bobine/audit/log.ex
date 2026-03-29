defmodule Bobine.Audit.Log do
  use Ecto.Schema
  import Ecto.Changeset

  alias Bobine.Accounts.Organization
  alias Bobine.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, Ecto.UUID
    field :changes, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :action,
      :resource_type,
      :resource_id,
      :changes,
      :metadata,
      :organization_id,
      :user_id
    ])
    |> validate_required([:action, :resource_type])
  end
end
