defmodule Bobine.Streaming.LiveEvent do
  @moduledoc """
  Schema for a live streaming event.

  A LiveEvent represents a scheduled or in-progress live stream tied to an
  organization. It has a state machine for status transitions and supports
  three access models: subscribers_only, public, and pay_per_view.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(draft scheduled live ended canceled did_not_occur)
  @valid_access_types ~w(subscribers_only public pay_per_view)

  # Valid state transitions (from → allowed tos)
  @transitions %{
    "draft" => ~w(scheduled canceled),
    "scheduled" => ~w(live canceled did_not_occur),
    "live" => ~w(ended),
    "ended" => [],
    "canceled" => [],
    "did_not_occur" => []
  }

  schema "live_events" do
    field :title, :string
    field :slug, :string
    field :description, :string
    field :cover_image_url, :string
    field :scheduled_start_at, :utc_datetime
    field :estimated_duration_minutes, :integer
    field :access_type, :string, default: "subscribers_only"
    field :ppv_price_cents, :integer
    field :ppv_access_window_hours, :integer, default: 48
    field :status, :string, default: "draft"
    field :mux_live_stream_id, :string
    field :mux_live_playback_id, :string
    field :mux_rtmp_url, :string
    field :stripe_product_id, :string
    field :stripe_price_id, :string
    field :went_live_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :canceled_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :recording_video, Bobine.Content.Video

    has_many :tickets, Bobine.Streaming.LiveEventTicket
    has_many :chat_messages, Bobine.Streaming.ChatMessage
    has_many :reminders, Bobine.Streaming.LiveEventReminder

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a live event.

  ## Examples

      iex> changeset(%Bobine.Streaming.LiveEvent{}, %{
      ...>   title: "My Stream",
      ...>   slug: "my-stream",
      ...>   scheduled_start_at: ~U[2026-05-01 18:00:00Z],
      ...>   access_type: "subscribers_only",
      ...>   organization_id: "00000000-0000-0000-0000-000000000001"
      ...> })
      %Ecto.Changeset{valid?: true}
  """
  def changeset(live_event, attrs) do
    live_event
    |> cast(attrs, [
      :title,
      :slug,
      :description,
      :cover_image_url,
      :scheduled_start_at,
      :estimated_duration_minutes,
      :access_type,
      :ppv_price_cents,
      :ppv_access_window_hours,
      :organization_id
    ])
    |> validate_required([:title, :slug, :scheduled_start_at, :access_type, :organization_id])
    |> validate_inclusion(:access_type, @valid_access_types)
    |> validate_ppv_price_when_required()
    |> unique_constraint(:slug, name: :live_events_slug_organization_id_index)
  end

  @doc """
  Changeset for Mux webhook-driven updates. Only allows Mux fields.

  ## Examples

      iex> mux_changeset(%Bobine.Streaming.LiveEvent{}, %{
      ...>   mux_live_stream_id: "abc123",
      ...>   mux_live_playback_id: "pb_xyz"
      ...> })
      %Ecto.Changeset{valid?: true}
  """
  def mux_changeset(live_event, attrs) do
    live_event
    |> cast(attrs, [
      :mux_live_stream_id,
      :mux_live_playback_id,
      :mux_rtmp_url,
      :recording_video_id
    ])
  end

  @doc """
  Changeset for state machine transitions. Validates the transition is allowed.

  Returns `{:error, :invalid_transition}` if the transition is not allowed per
  the `@transitions` map. Otherwise returns a changeset with the new status and
  any timestamp fields appropriate for the transition.

  ## Examples

      iex> event = %Bobine.Streaming.LiveEvent{status: "draft"}
      iex> cs = transition_changeset(event, "draft", "scheduled")
      iex> cs.valid?
      true

      iex> event = %Bobine.Streaming.LiveEvent{status: "ended"}
      iex> transition_changeset(event, "ended", "live")
      {:error, :invalid_transition}
  """
  def transition_changeset(live_event, from_status, to_status) do
    allowed = Map.get(@transitions, from_status, [])

    if to_status in allowed do
      live_event
      |> change(status: to_status)
      |> validate_inclusion(:status, @valid_statuses)
      |> apply_transition_timestamps(to_status)
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Returns the valid access types for a live event.

  ## Examples

      iex> Bobine.Streaming.LiveEvent.valid_access_types()
      ~w(subscribers_only public pay_per_view)
  """
  def valid_access_types, do: @valid_access_types

  @doc """
  Returns the valid statuses for a live event.

  ## Examples

      iex> Bobine.Streaming.LiveEvent.valid_statuses()
      ~w(draft scheduled live ended canceled did_not_occur)
  """
  def valid_statuses, do: @valid_statuses

  defp validate_ppv_price_when_required(changeset) do
    case get_field(changeset, :access_type) do
      "pay_per_view" ->
        changeset
        |> validate_required([:ppv_price_cents])
        |> validate_number(:ppv_price_cents, greater_than: 0)

      _ ->
        changeset
    end
  end

  defp apply_transition_timestamps(changeset, "live") do
    put_change(changeset, :went_live_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp apply_transition_timestamps(changeset, "ended") do
    put_change(changeset, :ended_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp apply_transition_timestamps(changeset, "canceled") do
    put_change(changeset, :canceled_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp apply_transition_timestamps(changeset, _status), do: changeset
end
