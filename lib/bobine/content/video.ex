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
    field :visibility, :string, default: "subscribers_only"
    field :custom_thumbnail_url, :string
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization

    has_one :episode, Bobine.Content.Episode

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
      :visibility,
      :custom_thumbnail_url,
      :organization_id
    ])
    |> validate_required([:title, :slug, :organization_id])
    |> validate_inclusion(:visibility, ~w(public free_with_account subscribers_only))
    |> unique_constraint(:slug, name: :videos_slug_organization_id_index)
  end

  @doc """
  Changeset for Mux webhook-driven status updates.
  Only allows fields that Mux webhooks should set.
  """
  def mux_status_changeset(video, attrs) do
    video
    |> cast(attrs, [:mux_asset_id, :mux_playback_id, :mux_status, :duration, :max_resolution])
    |> validate_required([:mux_status])
    |> validate_inclusion(:mux_status, ~w(waiting preparing ready errored))
  end
end
