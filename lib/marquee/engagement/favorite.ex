defmodule Marquee.Engagement.Favorite do
  @moduledoc """
  A viewer's favorited video. Uses soft deletes so toggle behavior can
  restore previously removed favorites without creating duplicates.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "favorites" do
    field :deleted_at, :utc_datetime

    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :user, Marquee.Accounts.User
    belongs_to :viewer, Marquee.Viewers.Viewer
    belongs_to :video, Marquee.Content.Video

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:organization_id, :user_id, :video_id])
    |> validate_required([:organization_id, :user_id, :video_id])
    |> unique_constraint([:user_id, :video_id, :organization_id])
  end

  @doc false
  def viewer_changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:organization_id, :viewer_id, :video_id])
    |> validate_required([:organization_id, :viewer_id, :video_id])
    |> unique_constraint([:viewer_id, :video_id, :organization_id])
  end
end
