defmodule Bobine.Catalog.Row do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rows" do
    field :title, :string
    field :source_type, Ecto.Enum, values: [:curated, :algorithm, :filter, :personalized]
    field :filter_config, :map
    field :position, :integer
    field :visible, :boolean, default: false
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(row, attrs) do
    row
    |> cast(attrs, [:title, :source_type, :filter_config, :position, :visible, :organization_id])
    |> validate_required([:title, :source_type, :position, :organization_id])
  end
end
