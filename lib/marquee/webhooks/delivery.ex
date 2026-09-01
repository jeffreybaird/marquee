defmodule Marquee.Webhooks.Delivery do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webhook_deliveries" do
    field :event_type, :string
    field :payload, :map
    field :response_status, :integer
    field :response_body, :string
    field :attempts, :integer
    field :delivered_at, :utc_datetime

    belongs_to :endpoint, Marquee.Webhooks.Endpoint

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :event_type,
      :payload,
      :response_status,
      :response_body,
      :attempts,
      :delivered_at,
      :endpoint_id
    ])
    |> validate_required([:event_type, :response_status, :attempts, :endpoint_id])
  end
end
