defmodule Bobine.Engagement.ContinueWatchingDismissal do
  @moduledoc """
  Records that a viewer has dismissed a card from the continue watching row.

  Keyed by either `video_id` (standalone video) or `series_id` (episode series).
  Exactly one of the two must be set per row.

  A dismissed item resurfaces automatically when the viewer's progress
  `last_activity_at` advances past `dismissed_at` — no cleanup required.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "continue_watching_dismissals" do
    field :dismissed_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :viewer, Bobine.Viewers.Viewer
    belongs_to :video, Bobine.Content.Video
    belongs_to :series, Bobine.Content.Series

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for dismissing a standalone video from continue watching.

      iex> changeset = Bobine.Engagement.ContinueWatchingDismissal.video_changeset(
      ...>   %Bobine.Engagement.ContinueWatchingDismissal{},
      ...>   %{organization_id: "org-1", viewer_id: "viewer-1", video_id: "video-1",
      ...>     dismissed_at: ~U[2024-01-01 12:00:00Z]}
      ...> )
      iex> changeset.valid?
      true
  """
  def video_changeset(dismissal, attrs) do
    dismissal
    |> cast(attrs, [:organization_id, :viewer_id, :video_id, :dismissed_at])
    |> validate_required([:organization_id, :viewer_id, :video_id, :dismissed_at])
    |> unique_constraint([:viewer_id, :video_id, :organization_id],
      name: :continue_watching_dismissals_viewer_video_org_unique
    )
  end

  @doc """
  Changeset for dismissing a series card from continue watching.

      iex> changeset = Bobine.Engagement.ContinueWatchingDismissal.series_changeset(
      ...>   %Bobine.Engagement.ContinueWatchingDismissal{},
      ...>   %{organization_id: "org-1", viewer_id: "viewer-1", series_id: "series-1",
      ...>     dismissed_at: ~U[2024-01-01 12:00:00Z]}
      ...> )
      iex> changeset.valid?
      true
  """
  def series_changeset(dismissal, attrs) do
    dismissal
    |> cast(attrs, [:organization_id, :viewer_id, :series_id, :dismissed_at])
    |> validate_required([:organization_id, :viewer_id, :series_id, :dismissed_at])
    |> unique_constraint(:series_id,
      name: :continue_watching_dismissals_viewer_series_org_unique
    )
  end
end
