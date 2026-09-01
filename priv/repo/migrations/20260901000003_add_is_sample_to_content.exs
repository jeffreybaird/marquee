defmodule Marquee.Repo.Migrations.AddIsSampleToContent do
  use Ecto.Migration

  # Flags starter/sample content seeded into a new org at signup so it can be
  # (a) exempted from the trial's total-duration cap and (b) removed in one
  # click. Partial indexes support the "clear all sample content" query.
  def change do
    for table <- [:videos, :collections, :rows] do
      alter table(table) do
        add :is_sample, :boolean, default: false, null: false
      end

      create index(table, [:organization_id], where: "is_sample", name: "#{table}_sample_index")
    end
  end
end
