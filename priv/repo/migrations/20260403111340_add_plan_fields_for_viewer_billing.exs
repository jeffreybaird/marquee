defmodule Bobine.Repo.Migrations.AddPlanFieldsForViewerBilling do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add :description, :text
      add :currency, :string, default: "usd", null: false
      add :trial_period_days, :integer
      add :position, :integer, default: 0, null: false
      add :features, {:array, :string}, default: [], null: false
    end
  end
end
