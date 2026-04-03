defmodule Bobine.Engagement.WatchlistItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "watchlist_items" do
    field :position, :integer
    field :auto_remove_on_watch, :boolean, default: false
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :user, Bobine.Accounts.User
    belongs_to :viewer, Bobine.Viewers.Viewer
    belongs_to :video, Bobine.Content.Video

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(watchlist_item, attrs) do
    watchlist_item
    |> cast(attrs, [:position, :auto_remove_on_watch, :organization_id, :user_id, :video_id])
    |> validate_required([:organization_id, :user_id, :video_id])
    |> unique_constraint([:user_id, :video_id, :organization_id])
  end

  @doc false
  def viewer_changeset(watchlist_item, attrs) do
    watchlist_item
    |> cast(attrs, [:position, :organization_id, :viewer_id, :video_id])
    |> validate_required([:organization_id, :viewer_id, :video_id])
    |> unique_constraint([:viewer_id, :video_id, :organization_id])
  end
end
