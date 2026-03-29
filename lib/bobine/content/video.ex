defmodule Bobine.Content.Video do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "videos" do
    field :title, :string
    field :slug, :string
    field :description, :string
    field :mux_asset_id, :string
    field :mux_playback_id, :string
    field :mux_upload_id, :string
    field :mux_status, :string
    field :duration, :float
    field :max_resolution, :string
    field :published, :boolean, default: false
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(video, attrs) do
    video
    |> cast(attrs, [
      :title,
      :slug,
      :description,
      :mux_asset_id,
      :mux_playback_id,
      :mux_upload_id,
      :mux_status,
      :duration,
      :max_resolution,
      :published,
      :organization_id
    ])
    |> validate_required([:title, :slug, :organization_id])
  end
end
