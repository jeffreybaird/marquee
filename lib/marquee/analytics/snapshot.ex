defmodule Marquee.Analytics.Snapshot do
  @moduledoc """
  Daily pre-computed analytics snapshot for an organization.

  Each row captures one metric value (e.g. daily_subscribers, daily_revenue)
  for one organization on one date. The unique index on
  (organization_id, period_date, metric_type) makes upserts idempotent.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @metric_types ~w(daily_subscribers daily_revenue daily_views daily_watch_time)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "analytics_snapshots" do
    field :period_date, :date
    field :metric_type, :string
    field :value, :decimal
    field :metadata, :map, default: %{}

    belongs_to :organization, Marquee.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for an analytics snapshot.

      iex> Marquee.Analytics.Snapshot.changeset(%Marquee.Analytics.Snapshot{}, %{
      ...>   organization_id: "00000000-0000-0000-0000-000000000001",
      ...>   period_date: ~D[2026-01-01],
      ...>   metric_type: "daily_views",
      ...>   value: Decimal.new("42")
      ...> })
      |> Map.get(:valid?)
      true
  """
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:organization_id, :period_date, :metric_type, :value, :metadata])
    |> validate_required([:organization_id, :period_date, :metric_type, :value])
    |> validate_inclusion(:metric_type, @metric_types)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:organization_id, :period_date, :metric_type],
      name: :analytics_snapshots_organization_id_period_date_metric_type_ind
    )
  end

  @doc "Valid metric type atoms for snapshots."
  def metric_types, do: @metric_types
end
