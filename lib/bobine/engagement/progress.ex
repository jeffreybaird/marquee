defmodule Bobine.Engagement.Progress do
  @moduledoc """
  Tracks a viewer's playback position in a video. Updated via the progress
  buffer to avoid high-frequency direct DB writes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "progresses" do
    field :position, :float
    field :completed, :boolean, default: false
    field :duration, :float

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :user, Bobine.Accounts.User
    belongs_to :viewer, Bobine.Viewers.Viewer
    belongs_to :video, Bobine.Content.Video

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [
      :position,
      :completed,
      :duration,
      :organization_id,
      :user_id,
      :viewer_id,
      :video_id
    ])
    |> validate_required([:position, :organization_id, :video_id])
    |> unique_constraint([:user_id, :video_id, :organization_id])
    |> unique_constraint([:viewer_id, :video_id, :organization_id])
  end
end
