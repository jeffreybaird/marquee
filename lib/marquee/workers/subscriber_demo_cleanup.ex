defmodule Marquee.Workers.SubscriberDemoCleanup do
  @moduledoc """
  Erases expired demo sessions in bounded batches on the bulk queue.
  Scheduled jobs carry `organization_id`. The cron invocation is an explicit
  platform dispatcher exception: it discovers organizations with demo viewers and
  enqueues tenant-scoped cleanup, following the platform maintenance workers.
  """
  use Oban.Worker, queue: :bulk, max_attempts: 5

  alias Marquee.{Accounts, Admin, SubscriberDemo}

  @impl true
  def perform(%Oban.Job{args: %{"organization_id" => org_id}}) do
    with {:ok, org} <- Accounts.get_organization(org_id),
         {:ok, count} <- SubscriberDemo.cleanup_expired(org) do
      if count == 100, do: %{organization_id: org.id} |> new() |> Oban.insert!()
      :ok
    end
  end

  # The cron entry discovers a bounded page, then enqueues tenant-scoped cleanup.
  def perform(%Oban.Job{args: args}) do
    organization_ids =
      Admin.list_subscriber_demo_cleanup_organization_ids(after_id: args["after_id"])

    Enum.each(organization_ids, fn org_id ->
      %{organization_id: org_id} |> new() |> Oban.insert!()
    end)

    if length(organization_ids) == 100 do
      %{after_id: List.last(organization_ids)} |> new() |> Oban.insert!()
    end

    :ok
  end
end
