defmodule Marquee.Content.Episode do
  @moduledoc """
  An episode links a video to a season at a specific position.

  The `title` field is an optional override — if nil, the video's title
  is used for display purposes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "episodes" do
    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :season, Marquee.Content.Season
    belongs_to :video, Marquee.Content.Video

    field :episode_number, :integer
    field :title, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for an episode.

  Exempt from doctest — requires database for constraint checks.
  """
  def changeset(episode, attrs) do
    episode
    |> cast(attrs, [:episode_number, :title, :video_id])
    |> validate_required([:episode_number, :video_id])
    |> validate_number(:episode_number, greater_than: 0)
    |> unique_constraint([:season_id, :episode_number])
    |> unique_constraint([:season_id, :video_id])
    |> foreign_key_constraint(:video_id)
    |> foreign_key_constraint(:season_id)
  end
end
