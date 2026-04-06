defmodule Bobine.Content.CollectionItem do
  @moduledoc """
  A polymorphic join between a collection and a content entity.

  Each item references exactly one of: video, season, or series, determined
  by the `item_type` field. Items are ordered by `position` within their
  collection.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "collection_items" do
    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :collection, Bobine.Content.Collection
    belongs_to :video, Bobine.Content.Video
    belongs_to :season, Bobine.Content.Season
    belongs_to :series, Bobine.Content.Series

    field :item_type, Ecto.Enum, values: [:video, :season, :series]
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a collection item.

  Validates that exactly one FK is set, matching the `item_type`.

  Exempt from doctest — requires database for constraint checks.
  """
  def changeset(collection_item, attrs) do
    collection_item
    |> cast(attrs, [
      :item_type,
      :position,
      :organization_id,
      :collection_id,
      :video_id,
      :season_id,
      :series_id
    ])
    |> validate_required([:item_type, :position])
    |> validate_polymorphic_ref()
    |> unique_constraint([:collection_id, :video_id])
    |> unique_constraint([:collection_id, :season_id])
    |> unique_constraint([:collection_id, :series_id])
  end

  @doc """
  Returns the referenced entity for the given item based on its type.

      iex> Bobine.Content.CollectionItem.referenced_entity(%Bobine.Content.CollectionItem{item_type: :video, video: %{id: "1"}, season: nil, series: nil})
      %{id: "1"}

      iex> Bobine.Content.CollectionItem.referenced_entity(%Bobine.Content.CollectionItem{item_type: :season, video: nil, season: %{id: "2"}, series: nil})
      %{id: "2"}

      iex> Bobine.Content.CollectionItem.referenced_entity(%Bobine.Content.CollectionItem{item_type: :series, video: nil, season: nil, series: %{id: "3"}})
      %{id: "3"}
  """
  def referenced_entity(%__MODULE__{item_type: :video, video: video}), do: video
  def referenced_entity(%__MODULE__{item_type: :season, season: season}), do: season
  def referenced_entity(%__MODULE__{item_type: :series, series: series}), do: series

  defp validate_polymorphic_ref(changeset) do
    item_type = get_field(changeset, :item_type)
    video_id = get_field(changeset, :video_id)
    season_id = get_field(changeset, :season_id)
    series_id = get_field(changeset, :series_id)

    case item_type do
      :video ->
        changeset
        |> validate_required([:video_id])
        |> validate_no_field(:season_id, season_id)
        |> validate_no_field(:series_id, series_id)

      :season ->
        changeset
        |> validate_required([:season_id])
        |> validate_no_field(:video_id, video_id)
        |> validate_no_field(:series_id, series_id)

      :series ->
        changeset
        |> validate_required([:series_id])
        |> validate_no_field(:video_id, video_id)
        |> validate_no_field(:season_id, season_id)

      _ ->
        add_error(changeset, :item_type, "must be video, season, or series")
    end
  end

  defp validate_no_field(changeset, field, value) when not is_nil(value) do
    type_name = field |> Atom.to_string() |> String.trim_trailing("_id")
    add_error(changeset, field, "must be nil when item_type is not #{type_name}")
  end

  defp validate_no_field(changeset, _field, nil), do: changeset
end
