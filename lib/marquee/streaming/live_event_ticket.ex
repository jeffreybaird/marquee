defmodule Marquee.Streaming.LiveEventTicket do
  @moduledoc """
  Schema for pay-per-view tickets granting a viewer access to a live event.

  Tickets are purchased by viewers and give time-bounded access to a
  pay_per_view event. Supports soft delete for record-keeping.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "live_event_tickets" do
    field :stripe_payment_intent_id, :string
    field :stripe_charge_id, :string
    field :amount_cents, :integer
    field :access_starts_at, :utc_datetime
    field :access_ends_at, :utc_datetime
    field :refunded_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :live_event, Marquee.Streaming.LiveEvent
    belongs_to :viewer, Marquee.Viewers.Viewer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a live event ticket.

  ## Examples

      iex> changeset(%Marquee.Streaming.LiveEventTicket{}, %{
      ...>   amount_cents: 999,
      ...>   access_starts_at: ~U[2026-05-01 18:00:00Z],
      ...>   access_ends_at: ~U[2026-05-03 18:00:00Z],
      ...>   organization_id: "00000000-0000-0000-0000-000000000001",
      ...>   live_event_id: "00000000-0000-0000-0000-000000000002",
      ...>   viewer_id: "00000000-0000-0000-0000-000000000003"
      ...> })
      %Ecto.Changeset{valid?: true}
  """
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :stripe_payment_intent_id,
      :stripe_charge_id,
      :amount_cents,
      :access_starts_at,
      :access_ends_at,
      :organization_id,
      :live_event_id,
      :viewer_id
    ])
    |> validate_required([
      :amount_cents,
      :access_starts_at,
      :access_ends_at,
      :organization_id,
      :live_event_id,
      :viewer_id
    ])
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> unique_constraint([:live_event_id, :viewer_id],
      name: :live_event_tickets_live_event_id_viewer_id_index
    )
  end

  @doc """
  Changeset for marking a ticket as refunded.

  ## Examples

      iex> refund_changeset(%Marquee.Streaming.LiveEventTicket{}, %{refunded_at: ~U[2026-05-02 10:00:00Z]})
      %Ecto.Changeset{valid?: true}
  """
  def refund_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:refunded_at])
    |> validate_required([:refunded_at])
  end
end
