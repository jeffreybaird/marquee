defmodule Bobine.Engagement.WatchHistory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "watch_histories" do
    field :watched_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :user, Bobine.Accounts.User
    belongs_to :video, Bobine.Content.Video

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(watch_history, attrs) do
    watch_history
    |> cast(attrs, [:watched_at, :organization_id, :user_id, :video_id])
    |> validate_required([:watched_at, :organization_id, :user_id, :video_id])
  end
end
