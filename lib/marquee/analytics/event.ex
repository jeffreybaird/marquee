defmodule Marquee.Analytics.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "analytics_events" do
    field :event_type, :string
    field :metadata, :map
    field :occurred_at, :utc_datetime

    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :user, Marquee.Accounts.User
    belongs_to :viewer, Marquee.Viewers.Viewer
    belongs_to :video, Marquee.Content.Video

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :metadata, :occurred_at, :organization_id, :user_id, :video_id])
    |> validate_required([:event_type, :occurred_at, :organization_id])
  end
end
