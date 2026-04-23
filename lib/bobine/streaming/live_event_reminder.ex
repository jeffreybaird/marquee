defmodule Bobine.Streaming.LiveEventReminder do
  @moduledoc """
  Schema for viewer reminders for a live event.

  Viewers can opt-in to receive a reminder notification before a scheduled
  live event starts. `notified_at` is set when the reminder is dispatched.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "live_event_reminders" do
    field :notified_at, :utc_datetime

    belongs_to :organization, Bobine.Accounts.Organization
    belongs_to :live_event, Bobine.Streaming.LiveEvent
    belongs_to :viewer, Bobine.Viewers.Viewer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a live event reminder.

  ## Examples

      iex> changeset(%Bobine.Streaming.LiveEventReminder{}, %{
      ...>   organization_id: "00000000-0000-0000-0000-000000000001",
      ...>   live_event_id: "00000000-0000-0000-0000-000000000002",
      ...>   viewer_id: "00000000-0000-0000-0000-000000000003"
      ...> })
      %Ecto.Changeset{valid?: true}
  """
  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:organization_id, :live_event_id, :viewer_id, :notified_at])
    |> validate_required([:organization_id, :live_event_id, :viewer_id])
    |> unique_constraint([:live_event_id, :viewer_id],
      name: :live_event_reminders_live_event_id_viewer_id_index
    )
  end

  @doc """
  Changeset for marking a reminder as notified.

  ## Examples

      iex> notified_changeset(%Bobine.Streaming.LiveEventReminder{}, %{notified_at: ~U[2026-05-01 17:00:00Z]})
      %Ecto.Changeset{valid?: true}
  """
  def notified_changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:notified_at])
    |> validate_required([:notified_at])
  end
end
