defmodule Marquee.Content.ShortFeedItem do
  @moduledoc """
  One video in an organization's operator-curated Shorts feed, ordered by
  `position`. Join rows are hard-deleted on removal (the video itself is
  never touched), matching collection items.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "short_feed_items" do
    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :video, Marquee.Content.Video

    field :position, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:position])
    |> validate_required([:organization_id, :video_id, :position])
    |> unique_constraint([:organization_id, :video_id])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:video_id)
  end
end
