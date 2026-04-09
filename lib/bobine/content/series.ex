defmodule Bobine.Content.Series do
  @moduledoc """
  A series groups seasons and their episodes into a hierarchical content structure.

  Series belong to an organization and support soft deletion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "series" do
    belongs_to :organization, Bobine.Accounts.Organization

    field :title, :string
    field :slug, :string
    field :description, :string
    field :cover_image_url, :string
    field :position, :integer, default: 0
    field :visible, :boolean, default: true
    field :new_season, :boolean, default: false
    field :deleted_at, :utc_datetime

    has_many :seasons, Bobine.Content.Season

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a series.

  Exempt from doctest — requires database for slug uniqueness.
  """
  def changeset(series, attrs) do
    series
    |> cast(attrs, [
      :title,
      :description,
      :cover_image_url,
      :position,
      :visible,
      :new_season
    ])
    |> validate_required([:title])
    |> maybe_generate_slug()
    |> unique_constraint([:organization_id, :slug])
  end

  defp maybe_generate_slug(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :title) do
          nil -> changeset
          title -> put_change(changeset, :slug, Bobine.Slug.generate(title))
        end

      _slug ->
        changeset
    end
  end
end
