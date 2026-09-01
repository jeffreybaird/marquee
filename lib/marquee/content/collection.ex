defmodule Marquee.Content.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  alias Marquee.Content.{CollectionItem, Video}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "collections" do
    belongs_to :organization, Marquee.Accounts.Organization
    field :title, :string
    field :slug, :string
    field :description, :string
    field :cover_image_url, :string
    field :position, :integer, default: 0
    field :visible, :boolean, default: true
    field :deleted_at, :utc_datetime

    # Legacy fields kept for migration compatibility
    field :type, Ecto.Enum, values: [:series, :season, :category]
    belongs_to :parent, __MODULE__, foreign_key: :parent_id

    has_many :collection_items, CollectionItem
    many_to_many :videos, Video, join_through: CollectionItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [
      :title,
      :slug,
      :description,
      :cover_image_url,
      :position,
      :visible,
      :organization_id,
      :type,
      :parent_id
    ])
    |> validate_required([:title, :organization_id])
    |> maybe_generate_slug()
    |> unique_constraint([:organization_id, :slug])
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        put_change(changeset, :slug, Marquee.Content.slugify(get_field(changeset, :title) || ""))

      "" ->
        put_change(changeset, :slug, Marquee.Content.slugify(get_field(changeset, :title) || ""))

      _ ->
        changeset
    end
  end
end
