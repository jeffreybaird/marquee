defmodule Marquee.Workers.SubscriberDemoCleanup do
  @moduledoc """
  Erases expired demo sessions in bounded batches on the bulk queue.
  Scheduled jobs carry `organization_id`. The cron invocation is an explicit
  platform dispatcher exception: it resolves only the Workshop demo and
  enqueues tenant-scoped cleanup, following the platform maintenance workers.
  """
  use Oban.Worker, queue: :bulk, max_attempts: 5

  alias Marquee.{Accounts, SubscriberDemo}

  @impl true
  def perform(%Oban.Job{args: %{"organization_id" => org_id}}) do
    with {:ok, org} <- Accounts.get_organization(org_id),
         {:ok, count} <- SubscriberDemo.cleanup_expired(org) do
      if count == 100, do: %{organization_id: org.id} |> new() |> Oban.insert!()
      :ok
    end
  end

  # The cron entry is a platform-level recovery dispatcher. It resolves only
  # the explicitly named demo tenant and enqueues tenant-scoped cleanup.
  def perform(%Oban.Job{}) do
    case Accounts.get_organization_by_slug("the-workshop") do
      {:ok, org} ->
        %{organization_id: org.id} |> new() |> Oban.insert!()
        :ok

      {:error, :not_found} ->
        :ok
    end
  end
end
