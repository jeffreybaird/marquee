defmodule Marquee.Engagement.PlaybackDropOff do
  @moduledoc """
  Raw drop-off event: a viewer navigated away from a video without finishing.

  Events are processed by `Marquee.Workers.DropOffAggregator` after an hour,
  which discards rows where the viewer returned (or completed) and otherwise
  increments the matching `VideoDropOffBucket` counter.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @bucket_size_seconds 10

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "playback_drop_offs" do
    field :bucket, :integer
    field :max_position, :float
    field :video_duration, :float
    field :left_at, :utc_datetime
    field :counted_at, :utc_datetime
    field :outcome, :string

    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :video, Marquee.Content.Video
    belongs_to :viewer, Marquee.Viewers.Viewer
    belongs_to :user, Marquee.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the 10-second bucket index for a given playhead position in seconds.

  ## Examples

      iex> Marquee.Engagement.PlaybackDropOff.bucket_for(0.0)
      0

      iex> Marquee.Engagement.PlaybackDropOff.bucket_for(9.9)
      0

      iex> Marquee.Engagement.PlaybackDropOff.bucket_for(10.0)
      1

      iex> Marquee.Engagement.PlaybackDropOff.bucket_for(137.5)
      13
  """
  def bucket_for(position) when is_number(position) and position >= 0 do
    trunc(position / @bucket_size_seconds)
  end

  @doc """
  Returns the bucket size in seconds.

  ## Examples

      iex> Marquee.Engagement.PlaybackDropOff.bucket_size()
      10
  """
  def bucket_size, do: @bucket_size_seconds

  @doc false
  def changeset(drop_off, attrs) do
    drop_off
    |> cast(attrs, [
      :organization_id,
      :video_id,
      :viewer_id,
      :user_id,
      :bucket,
      :max_position,
      :video_duration,
      :left_at,
      :counted_at,
      :outcome
    ])
    |> validate_required([:organization_id, :video_id, :bucket, :max_position, :left_at])
    |> validate_number(:bucket, greater_than_or_equal_to: 0)
    |> validate_number(:max_position, greater_than_or_equal_to: 0)
    |> validate_inclusion(:outcome, ["counted", "discarded"])
    |> validate_subject_present()
  end

  defp validate_subject_present(changeset) do
    viewer_id = get_field(changeset, :viewer_id)
    user_id = get_field(changeset, :user_id)

    if is_nil(viewer_id) and is_nil(user_id) do
      add_error(changeset, :viewer_id, "either viewer_id or user_id must be set")
    else
      changeset
    end
  end
end
