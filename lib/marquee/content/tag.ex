defmodule Marquee.Content.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tags" do
    belongs_to :organization, Marquee.Accounts.Organization
    field :name, :string
    field :slug, :string
    field :deleted_at, :utc_datetime

    many_to_many :videos, Marquee.Content.Video, join_through: "video_tags"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :slug, :organization_id])
    |> validate_required([:name, :organization_id])
    |> normalize_name()
    |> maybe_generate_slug()
    |> unique_constraint([:slug, :organization_id])
  end

  defp normalize_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :name, String.downcase(name))
    end
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        put_change(changeset, :slug, Marquee.Content.slugify(get_field(changeset, :name) || ""))

      "" ->
        put_change(changeset, :slug, Marquee.Content.slugify(get_field(changeset, :name) || ""))

      _ ->
        changeset
    end
  end
end
