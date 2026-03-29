defmodule Bobine.Content.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "collections" do
    field :title, :string
    field :slug, :string
    field :description, :string
    field :type, Ecto.Enum, values: [:series, :season, :category]
    field :position, :integer
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :parent, Bobine.Content.Collection, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:title, :slug, :description, :type, :position, :organization_id, :parent_id])
    |> validate_required([:title, :slug, :type, :position, :organization_id])
  end
end
