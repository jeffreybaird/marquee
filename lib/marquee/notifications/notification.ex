defmodule Marquee.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "notifications" do
    field :title, :string
    field :body, :string
    field :type, Ecto.Enum, values: [:push, :email]
    field :status, Ecto.Enum, values: [:draft, :sent]
    field :sent_at, :utc_datetime
    field :deleted_at, :utc_datetime

    belongs_to :organization, Marquee.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:title, :body, :type, :status, :sent_at, :organization_id])
    |> validate_required([:title, :body, :type, :status, :organization_id])
  end
end
