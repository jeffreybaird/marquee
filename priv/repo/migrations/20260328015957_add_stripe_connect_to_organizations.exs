defmodule Bobine.Repo.Migrations.AddStripeConnectToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :stripe_connect_account_id, :string
      add :stripe_connect_onboarding_complete, :boolean, default: false, null: false
      add :stripe_customer_id, :string
    end
  end
end
