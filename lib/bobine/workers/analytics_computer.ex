defmodule Bobine.Workers.AnalyticsComputer do
  @moduledoc """
  Oban worker that computes and stores daily analytics snapshots.

  Runs every 6 hours for each active organization. Idempotent — running
  twice for the same day produces the same result via upsert.

  Computes for yesterday: daily_subscribers, daily_revenue, daily_views,
  daily_watch_time.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3

  import Ecto.Query

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Bobine.Accounts.Organization
  alias Bobine.Analytics
  alias Bobine.Billing.{Plan, ViewerSubscription}
  alias Bobine.Engagement.Progress
  alias Bobine.Repo

  @impl true
  def perform(%Oban.Job{args: %{"dispatch" => true}, attempt: attempt}) do
    Logger.metadata(worker: "AnalyticsComputer")
    Tracer.set_attributes([{"oban.attempt", attempt}])

    Tracer.with_span "bobine.worker.analytics_computer.dispatch" do
      Organization
      |> where([o], is_nil(o.deleted_at))
      |> select([o], o.id)
      |> Repo.all()
      |> Enum.each(fn org_id ->
        %{"organization_id" => org_id}
        |> new()
        |> Oban.insert()
      end)

      :ok
    end
  end

  @impl true
  def perform(%Oban.Job{args: %{"organization_id" => org_id}, attempt: attempt}) do
    Logger.metadata(org_id: org_id, worker: "AnalyticsComputer")
    Tracer.set_attributes([{"bobine.org.id", org_id}, {"oban.attempt", attempt}])

    Tracer.with_span "bobine.worker.analytics_computer" do
      case Repo.get(Organization, org_id) do
        nil ->
          Logger.warning("AnalyticsComputer: organization not found", organization_id: org_id)
          {:ok, :not_found}

        org ->
          compute_snapshots_for_org(org)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp compute_snapshots_for_org(%Organization{id: org_id} = _org) do
    yesterday = Date.add(Date.utc_today(), -1)

    metrics = [
      {"daily_subscribers", fn -> compute_daily_subscribers(org_id) end},
      {"daily_revenue", fn -> compute_daily_revenue(org_id) end},
      {"daily_views", fn -> compute_daily_views(org_id, yesterday) end},
      {"daily_watch_time", fn -> compute_daily_watch_time(org_id, yesterday) end}
    ]

    Enum.each(metrics, fn {metric_type, compute_fn} ->
      try do
        value = compute_fn.()

        Analytics.upsert_snapshot(%{
          organization_id: org_id,
          period_date: yesterday,
          metric_type: metric_type,
          value: Decimal.new(to_string(value))
        })
      rescue
        error ->
          Logger.error("AnalyticsComputer: failed to compute metric",
            metric_type: metric_type,
            organization_id: org_id,
            error: inspect(error)
          )
      end
    end)

    :ok
  end

  defp compute_daily_subscribers(org_id) do
    ViewerSubscription
    |> where([s], s.organization_id == ^org_id)
    |> where([s], s.status in ["active", "trialing"])
    |> where([s], is_nil(s.deleted_at))
    |> Repo.aggregate(:count, :id)
  end

  defp compute_daily_revenue(org_id) do
    active_subs =
      ViewerSubscription
      |> join(:inner, [s], p in Plan, on: s.plan_id == p.id)
      |> where([s, _p], s.organization_id == ^org_id)
      |> where([s, _p], s.status in ["active", "trialing"])
      |> where([s, _p], is_nil(s.deleted_at))
      |> select([s, p], %{amount: p.amount, interval: p.interval, fee: s.application_fee_percent})
      |> Repo.all()

    Enum.reduce(active_subs, 0, fn sub, acc ->
      net = sub.amount * (1 - Decimal.to_float(sub.fee) / 100)
      monthly = if sub.interval == :yearly, do: net / 12, else: net
      acc + round(monthly)
    end)
  end

  defp compute_daily_views(org_id, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    Progress
    |> where([p], p.organization_id == ^org_id)
    |> where([p], p.position > 30.0)
    |> where([p], p.updated_at >= ^start_dt and p.updated_at <= ^end_dt)
    |> select([p], {p.viewer_id, p.video_id})
    |> distinct(true)
    |> Repo.all()
    |> length()
  end

  defp compute_daily_watch_time(org_id, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    result =
      Progress
      |> where([p], p.organization_id == ^org_id)
      |> where([p], p.updated_at >= ^start_dt and p.updated_at <= ^end_dt)
      |> Repo.aggregate(:sum, :position)

    case result do
      nil -> 0
      total -> round(Decimal.to_float(total))
    end
  end
end
