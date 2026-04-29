defmodule Bobine.Podcasts.Episode do
  @moduledoc """
  Schema for a single podcast Episode.

  An episode references a single audio source. For a Show with
  `source_type: "direct_upload"`, the audio lives in Mux and the episode
  carries the Mux identifiers; for a Show with `source_type: "feed_import"`,
  the audio lives at `remote_audio_url` and Bobine proxies access through
  the audio proxy. The downstream feed-generation and access-control code
  is uniform across both source types.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Bobine.Podcasts.Show

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(draft processing published withdrawn errored)
  @episode_types ~w(full trailer bonus)
  @mux_statuses ~w(waiting preparing ready errored)

  schema "podcast_episodes" do
    field :guid, :string
    field :title, :string
    field :description, :string
    field :episode_number, :integer
    field :season_number, :integer
    field :episode_type, :string, default: "full"
    field :publish_date, :utc_datetime
    field :duration_seconds, :integer
    field :explicit, :boolean

    field :mux_asset_id, :string
    field :mux_playback_id, :string
    field :mux_upload_id, :string
    field :mux_status, :string
    field :mp3_byte_size, :integer

    field :remote_audio_url, :string
    field :remote_audio_byte_size, :integer
    field :remote_audio_content_type, :string

    field :overrides_locked, :boolean, default: false
    field :locked_fields, {:array, :string}, default: []

    field :status, :string, default: "draft"
    field :error_message, :string
    field :withdrawn_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :show, Show

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(episode, attrs) do
    episode
    |> cast(attrs, [
      :organization_id,
      :show_id,
      :guid,
      :title,
      :description,
      :episode_number,
      :season_number,
      :episode_type,
      :publish_date,
      :duration_seconds,
      :explicit,
      :mux_asset_id,
      :mux_playback_id,
      :mux_upload_id,
      :mux_status,
      :mp3_byte_size,
      :remote_audio_url,
      :remote_audio_byte_size,
      :remote_audio_content_type,
      :overrides_locked,
      :locked_fields,
      :status,
      :error_message,
      :withdrawn_at
    ])
    |> validate_required([:organization_id, :show_id, :guid, :title, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:episode_type, @episode_types)
    |> maybe_validate_mux_status()
    |> unique_constraint([:show_id, :guid], name: :podcast_episodes_show_id_guid_index)
  end

  @doc false
  def mux_status_changeset(episode, attrs) do
    episode
    |> cast(attrs, [
      :mux_asset_id,
      :mux_playback_id,
      :mux_status,
      :duration_seconds,
      :mp3_byte_size,
      :status,
      :error_message
    ])
    |> validate_inclusion(:mux_status, @mux_statuses)
  end

  @doc false
  def lock_overrides_changeset(episode, locked_fields) when is_list(locked_fields) do
    episode
    |> change(overrides_locked: true, locked_fields: Enum.uniq(locked_fields))
  end

  @doc "Statuses that count as visible to subscriber feeds."
  def published_statuses, do: ["published"]

  @doc "Returns the canonical list of statuses."
  def statuses, do: @statuses

  @doc "Returns the canonical list of episode_type values."
  def episode_types, do: @episode_types

  defp maybe_validate_mux_status(changeset) do
    case get_field(changeset, :mux_status) do
      nil -> changeset
      _ -> validate_inclusion(changeset, :mux_status, @mux_statuses)
    end
  end
end
