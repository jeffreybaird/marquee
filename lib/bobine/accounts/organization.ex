defmodule Bobine.Accounts.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :custom_domain, :string
    field :stripe_account_id, :string
    field :stripe_connect_account_id, :string
    field :stripe_connect_onboarding_complete, :boolean, default: false
    field :stripe_customer_id, :string
    field :template, :string, default: "default"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug, :custom_domain, :stripe_account_id, :stripe_connect_account_id, :stripe_connect_onboarding_complete, :stripe_customer_id, :template])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> unique_constraint(:custom_domain)
  end
end
