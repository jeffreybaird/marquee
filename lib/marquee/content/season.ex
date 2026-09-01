defmodule Marquee.Content.Season do
  @moduledoc """
  A season belongs to a series and contains episodes.

  Seasons are ordered by `season_number` within their series and maintain
  a cached `episode_count` that is updated when episodes are added or removed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "seasons" do
    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :series, Marquee.Content.Series

    field :title, :string
    field :slug, :string
    field :description, :string
    field :cover_image_url, :string
    field :season_number, :integer
    field :episode_count, :integer, default: 0
    field :visible, :boolean, default: true
    field :deleted_at, :utc_datetime

    has_many :episodes, Marquee.Content.Episode

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a season.

  Exempt from doctest — requires database for constraint checks.
  """
  def changeset(season, attrs) do
    season
    |> cast(attrs, [:title, :description, :cover_image_url, :season_number, :visible])
    |> validate_required([:title, :season_number])
    |> validate_number(:season_number, greater_than: 0)
    |> maybe_generate_slug()
    |> unique_constraint([:series_id, :season_number])
    |> unique_constraint([:series_id, :slug])
  end

  defp maybe_generate_slug(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :title) do
          nil -> changeset
          title -> put_change(changeset, :slug, Marquee.Slug.generate(title))
        end

      _slug ->
        changeset
    end
  end
end
