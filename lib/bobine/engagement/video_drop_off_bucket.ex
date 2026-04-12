defmodule Bobine.Engagement.VideoDropOffBucket do
  @moduledoc """
  Per-video aggregate counter of confirmed drop-offs in a 10-second bucket.

  Populated by `Bobine.Workers.DropOffAggregator` after the 1-hour return
  window has elapsed on each `PlaybackDropOff` event.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "video_drop_off_buckets" do
    field :bucket, :integer
    field :count, :integer, default: 0

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :video, Bobine.Content.Video

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, [:organization_id, :video_id, :bucket, :count])
    |> validate_required([:organization_id, :video_id, :bucket, :count])
    |> validate_number(:bucket, greater_than_or_equal_to: 0)
    |> validate_number(:count, greater_than_or_equal_to: 0)
    |> unique_constraint([:video_id, :bucket])
  end
end
