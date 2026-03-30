defmodule Bobine.Content.CollectionItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "collection_items" do
    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :collection, Bobine.Content.Collection
    belongs_to :video, Bobine.Content.Video
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(collection_item, attrs) do
    collection_item
    |> cast(attrs, [:position, :organization_id, :collection_id, :video_id])
    |> validate_required([:organization_id, :collection_id, :video_id])
    |> unique_constraint([:collection_id, :video_id])
  end
end
