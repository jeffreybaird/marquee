defmodule Bobine.Webhooks.Endpoint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webhook_endpoints" do
    field :url, :string
    field :secret, :string
    field :events, {:array, :string}
    field :active, :boolean, default: false
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:url, :secret, :events, :active, :organization_id])
    |> validate_required([:url, :secret, :events, :organization_id])
  end
end
