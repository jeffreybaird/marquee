defmodule Bobine.Catalog.Row do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rows" do
    belongs_to :organization, Bobine.Accounts.Organization
    field :title, :string

    field :source_type, Ecto.Enum,
      values: [:curated, :collection, :tag, :recent, :continue_watching, :popular]

    field :source_id, :binary_id
    field :filter_config, :map
    field :position, :integer, default: 0
    field :visible, :boolean, default: false
    field :max_items, :integer, default: 20
    field :deleted_at, :utc_datetime

    has_many :row_items, Bobine.Catalog.RowItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :title,
      :source_type,
      :source_id,
      :filter_config,
      :position,
      :visible,
      :max_items,
      :organization_id
    ])
    |> validate_required([:title, :source_type, :organization_id])
    |> validate_number(:max_items, greater_than_or_equal_to: 5, less_than_or_equal_to: 50)
    |> validate_source_id()
  end

  defp validate_source_id(changeset) do
    source_type = get_field(changeset, :source_type)

    if source_type in [:collection, :tag] do
      validate_required(changeset, [:source_id])
    else
      changeset
    end
  end
end
