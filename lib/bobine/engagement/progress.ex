defmodule Bobine.Engagement.Progress do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "progresses" do
    field :position, :float
    field :completed, :boolean, default: false

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :user, Bobine.Accounts.User
    belongs_to :video, Bobine.Content.Video

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:position, :completed, :organization_id, :user_id, :video_id])
    |> validate_required([:position, :organization_id, :user_id, :video_id])
    |> unique_constraint([:user_id, :video_id, :organization_id])
  end
end
