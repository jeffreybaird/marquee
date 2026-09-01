defmodule Marquee.Content.VideoTag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "video_tags" do
    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :video, Marquee.Content.Video
    belongs_to :tag, Marquee.Content.Tag

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(video_tag, attrs) do
    video_tag
    |> cast(attrs, [:organization_id, :video_id, :tag_id])
    |> validate_required([:organization_id, :video_id, :tag_id])
    |> unique_constraint([:video_id, :tag_id])
  end
end
