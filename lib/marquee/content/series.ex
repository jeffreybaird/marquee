defmodule Marquee.Content.Series do
  @moduledoc """
  A series groups seasons and their episodes into a hierarchical content structure.

  Series belong to an organization and support soft deletion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "series" do
    belongs_to :organization, Marquee.Accounts.Organization

    field :title, :string
    field :slug, :string
    field :description, :string
    field :cover_image_url, :string
    field :position, :integer, default: 0
    field :visible, :boolean, default: true
    field :new_season, :boolean, default: false
    field :new_season_expires_at, :utc_datetime
    field :deleted_at, :utc_datetime

    has_many :seasons, Marquee.Content.Season

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
      :new_season,
      :new_season_expires_at
    ])
    |> maybe_clear_new_season_expiry()
    |> validate_required([:title])
    |> maybe_generate_slug()
    |> unique_constraint([:organization_id, :slug])
  end

  # If the operator clears the new_season flag, also clear any expiry so the
  # next time they re-enable the badge they're not surprised by a stale date.
  defp maybe_clear_new_season_expiry(changeset) do
    case fetch_change(changeset, :new_season) do
      {:ok, false} -> put_change(changeset, :new_season_expires_at, nil)
      _ -> changeset
    end
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
