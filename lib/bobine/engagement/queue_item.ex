defmodule Bobine.Engagement.QueueItem do
  @moduledoc """
  A video in a viewer's playback queue.

  Queue items are ephemeral — they are hard-deleted when removed (no soft
  deletes). The queue is an ordered list of videos the viewer intends to
  watch, similar to Spotify's playback queue.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "queue_items" do
    field :position, :integer
    field :added_from, :string
    field :added_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :viewer, Bobine.Viewers.Viewer
    belongs_to :video, Bobine.Content.Video

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(queue_item, attrs) do
    queue_item
    |> cast(attrs, [:position, :added_from, :added_at, :organization_id, :viewer_id, :video_id])
    |> validate_required([:position, :organization_id, :viewer_id, :video_id])
    |> validate_inclusion(:added_from, ["browse", "collection", "search", "related", "go_back"])
    |> unique_constraint([:organization_id, :viewer_id, :video_id])
  end
end
