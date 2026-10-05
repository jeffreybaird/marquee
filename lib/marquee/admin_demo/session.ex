defmodule Marquee.AdminDemo.Session do
  @moduledoc "Hashed, host-bound capability for one disposable admin sandbox."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "admin_demo_sessions" do
    belongs_to :organization, Marquee.Accounts.Organization
    belongs_to :user, Marquee.Accounts.User
    belongs_to :owner_user, Marquee.Accounts.User
    belongs_to :replacement_session, __MODULE__
    field :token_hash, :binary, redact: true
    field :entry_key_hash, :binary, redact: true
    field :hostname, :string
    field :template_version, :string
    field :generation, Ecto.UUID
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :purged_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
