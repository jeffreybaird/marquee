defmodule Marquee.Podcasts.Show do
  @moduledoc """
  Schema for a premium podcast Show.

  A Show belongs to exactly one Organization. Its `source_type` is fixed for
  the lifetime of the show — switching between `direct_upload` and
  `feed_import` would require migrating every episode's audio source and
  regenerating GUIDs, so the changeset blocks the change.

  Access is mediated by `access_mode`:

    * `"any_active"` — any subscriber with an active subscription to any plan
      can access (default, simplest configuration).
    * `"specific_tiers"` — a subset of plans grant access. The `show_tiers`
      join records list which plans qualify.
    * `"audio_only_plan"` — the show is bundled with a single plan that
      subscribers purchase independently. The `audio_only_plan` association
      points at that plan.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Marquee.Billing.Plan
  alias Marquee.Podcasts.{Episode, ShowTier}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(direct_upload feed_import)
  @access_modes ~w(any_active specific_tiers audio_only_plan)

  schema "podcast_shows" do
    field :source_type, :string, default: "direct_upload"
    field :remote_feed_url, :string
    field :remote_last_synced_at, :utc_datetime
    field :remote_last_sync_error, :string
    field :remote_consecutive_failures, :integer, default: 0

    field :title, :string
    field :slug, :string
    field :description, :string
    field :author, :string
    field :owner_name, :string
    field :owner_email, :string
    field :language, :string, default: "en-us"
    field :primary_category, :string
    field :secondary_categories, {:array, :string}, default: []
    field :explicit, :boolean, default: false
    field :copyright, :string
    field :cover_artwork_url, :string

    field :access_mode, :string, default: "any_active"
    field :published, :boolean, default: false
    field :deleted_at, :utc_datetime

    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :audio_only_plan, Plan

    has_many :show_tiers, ShowTier, foreign_key: :show_id
    has_many :access_plans, through: [:show_tiers, :plan]
    has_many :episodes, Episode, foreign_key: :show_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(show, attrs) do
    show
    |> cast(attrs, [
      :source_type,
      :remote_feed_url,
      :title,
      :slug,
      :description,
      :author,
      :owner_name,
      :owner_email,
      :language,
      :primary_category,
      :secondary_categories,
      :explicit,
      :copyright,
      :cover_artwork_url,
      :access_mode,
      :audio_only_plan_id,
      :published,
      :organization_id
    ])
    |> validate_required([:title, :slug, :source_type, :access_mode, :organization_id])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:access_mode, @access_modes)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase letters, numbers and dashes"
    )
    |> validate_format(:owner_email, ~r/^[^@\s]+@[^@\s]+$/, message: "must be a valid email")
    |> validate_remote_feed_url()
    |> validate_audio_only_plan()
    |> prevent_source_type_change()
    |> unique_constraint([:slug, :organization_id],
      name: :podcast_shows_organization_id_slug_index
    )
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:audio_only_plan_id)
  end

  @doc false
  def remote_sync_changeset(show, attrs) do
    show
    |> cast(attrs, [
      :remote_last_synced_at,
      :remote_last_sync_error,
      :remote_consecutive_failures
    ])
  end

  @doc false
  def soft_delete_changeset(show) do
    change(show, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp validate_remote_feed_url(changeset) do
    case get_field(changeset, :source_type) do
      "feed_import" ->
        changeset
        |> validate_required([:remote_feed_url])
        |> validate_format(:remote_feed_url, ~r{^https?://}, message: "must be an http(s) URL")

      _ ->
        changeset
    end
  end

  defp validate_audio_only_plan(changeset) do
    case get_field(changeset, :access_mode) do
      "audio_only_plan" -> validate_required(changeset, [:audio_only_plan_id])
      _ -> changeset
    end
  end

  defp prevent_source_type_change(changeset) do
    cond do
      # New record — any source_type is fine.
      is_nil(changeset.data.id) -> changeset
      # Persisted record, no change cast — fine.
      is_nil(get_change(changeset, :source_type)) -> changeset
      # Persisted record with a real source_type change — reject.
      true -> add_error(changeset, :source_type, "cannot be changed after creation")
    end
  end

  @doc "Returns the list of allowed source_type values."
  def source_types, do: @source_types

  @doc "Returns the list of allowed access_mode values."
  def access_modes, do: @access_modes
end
