defmodule Marquee.TenantDomains.Domain do
  @moduledoc "An immutable hostname allocation and its durable provisioning progress."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tenant_domains" do
    belongs_to :organization, Marquee.Accounts.Organization
    field :hostname, :string
    field :host_pattern, :string
    field :dns_zone, :string
    field :target_ipv4, :string
    field :dns_record_id, :string
    field :generation, Ecto.UUID

    field :status, Ecto.Enum,
      values: [:pending_dns, :dns_ready, :ready, :failed],
      default: :pending_dns

    field :eligibility_source, Ecto.Enum, values: [:backend, :existing_organization]
    field :eligible_at, :utc_datetime_usec
    field :last_error, :string
    field :ready_at, :utc_datetime_usec
    field :lease_token, Ecto.UUID
    field :lease_expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(domain, attrs) do
    domain
    |> cast(attrs, [
      :hostname,
      :host_pattern,
      :dns_zone,
      :target_ipv4,
      :generation,
      :eligibility_source,
      :eligible_at
    ])
    |> validate_required([
      :organization_id,
      :hostname,
      :host_pattern,
      :dns_zone,
      :target_ipv4,
      :generation,
      :eligibility_source,
      :eligible_at
    ])
    |> unique_constraint(:organization_id)
    |> unique_constraint(:hostname)
    |> foreign_key_constraint(:organization_id)
  end
end
