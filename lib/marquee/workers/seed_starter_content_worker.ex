defmodule Marquee.Workers.SeedStarterContentWorker do
  @moduledoc """
  Seeds a newly-created organization with sample/starter content.

  Enqueued right after a self-service signup commits. Running async keeps a
  seeding hiccup from ever blocking or rolling back account creation, and the
  content is in place well before the magic-link round-trip lets the operator
  reach their dashboard. Idempotent — a re-run on an already-seeded org is a
  no-op (`Marquee.Onboarding.StarterContent.seed/1`).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Marquee.Accounts
  alias Marquee.Onboarding.StarterContent

  @impl true
  def perform(%Oban.Job{args: %{"organization_id" => org_id}}) do
    case Accounts.get_organization(org_id) do
      {:ok, org} ->
        seed(org)

      {:error, :not_found} ->
        # Org was deleted before the job ran — nothing to seed.
        Logger.info("Skipping starter-content seed for missing org", org_id: org_id)
        :ok
    end
  end

  defp seed(org) do
    case StarterContent.seed(org) do
      {:ok, :already_seeded} ->
        :ok

      {:ok, summary} ->
        Logger.info("Seeded starter content",
          org_id: org.id,
          videos: summary.videos,
          collections: summary.collections,
          rows: summary.rows
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to seed starter content",
          org_id: org.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
