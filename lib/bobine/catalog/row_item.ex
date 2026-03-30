defmodule Bobine.Catalog.RowItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "row_items" do
    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :row, Bobine.Catalog.Row
    belongs_to :video, Bobine.Content.Video
    field :position, :integer, default: 0
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(row_item, attrs) do
    row_item
    |> cast(attrs, [:position, :organization_id, :row_id, :video_id])
    |> validate_required([:organization_id, :row_id, :video_id])
  end
end
