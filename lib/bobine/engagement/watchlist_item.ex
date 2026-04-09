defmodule Bobine.Engagement.WatchlistItem do
  @moduledoc """
  Polymorphic watchlist entry.

  A watchlist item references one of three things — a video, a season, or
  a series — distinguished by `item_type`. Exactly one of `video_id`,
  `season_id`, or `series_id` is set per row; the rest are nil.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @item_types [:video, :season, :series]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "watchlist_items" do
    field :position, :integer
    field :auto_remove_on_watch, :boolean, default: false
    field :deleted_at, :utc_datetime
    field :item_type, Ecto.Enum, values: @item_types, default: :video

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :user, Bobine.Accounts.User
    belongs_to :viewer, Bobine.Viewers.Viewer
    belongs_to :video, Bobine.Content.Video
    belongs_to :season, Bobine.Content.Season
    belongs_to :series, Bobine.Content.Series

    timestamps(type: :utc_datetime)
  end

  def item_types, do: @item_types

  @doc false
  def changeset(watchlist_item, attrs) do
    watchlist_item
    |> cast(attrs, [:position, :auto_remove_on_watch, :organization_id, :user_id, :video_id])
    |> validate_required([:organization_id, :user_id, :video_id])
    |> put_change(:item_type, :video)
    |> unique_constraint([:user_id, :video_id, :organization_id])
  end

  @doc false
  def viewer_changeset(watchlist_item, attrs) do
    watchlist_item
    |> cast(attrs, [
      :position,
      :organization_id,
      :viewer_id,
      :video_id,
      :season_id,
      :series_id,
      :item_type
    ])
    |> validate_required([:organization_id, :viewer_id])
    |> validate_inclusion(:item_type, @item_types)
    |> validate_polymorphic_target()
    |> unique_constraint([:viewer_id, :video_id, :organization_id])
    |> unique_constraint(:season_id,
      name: :watchlist_items_viewer_season_org_unique,
      message: "is already in your watchlist"
    )
    |> unique_constraint(:series_id,
      name: :watchlist_items_viewer_series_org_unique,
      message: "is already in your watchlist"
    )
  end

  # Exactly one polymorphic FK must be present, matching item_type.
  defp validate_polymorphic_target(changeset) do
    case get_field(changeset, :item_type) do
      :video ->
        changeset
        |> validate_required([:video_id])
        |> validate_nil_for(:season_id)
        |> validate_nil_for(:series_id)

      :season ->
        changeset
        |> validate_required([:season_id])
        |> validate_nil_for(:video_id)
        |> validate_nil_for(:series_id)

      :series ->
        changeset
        |> validate_required([:series_id])
        |> validate_nil_for(:video_id)
        |> validate_nil_for(:season_id)

      _ ->
        changeset
    end
  end

  defp validate_nil_for(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _ -> add_error(changeset, field, "must be nil for this item_type")
    end
  end
end
