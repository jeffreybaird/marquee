defmodule Marquee.Workers.MarkEventsDidNotOccurWorker do
  @moduledoc """
  Periodic job that transitions stale scheduled events to `did_not_occur`.

  A `scheduled` event is considered to have not occurred if its
  `scheduled_start_at` is more than 30 minutes in the past and it is still
  in `scheduled` status — meaning no `video.live_stream.active` webhook arrived.

  Runs every 15 minutes via Oban cron. Cross-tenant by design — this is a
  platform-level operation. No `organization_id` in args (documented Admin exception).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  require Logger

  alias Marquee.Accounts.Scope
  alias Marquee.Repo
  alias Marquee.Streaming
  alias Marquee.Streaming.LiveEvent

  @grace_minutes 30

  @impl true
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@grace_minutes * 60, :second)

    stale_events =
      LiveEvent
      |> where([e], e.status == "scheduled")
      |> where([e], e.scheduled_start_at < ^cutoff)
      |> where([e], is_nil(e.deleted_at))
      |> Repo.all()

    Enum.each(stale_events, &transition_stale_event/1)
    :ok
  end

  defp transition_stale_event(event) do
    scope = %Scope{organization: %{id: event.organization_id}}

    case Streaming.transition_event(scope, event, "did_not_occur") do
      {:ok, _} ->
        Logger.info("Transitioned stale event to did_not_occur",
          live_event_id: event.id,
          org_id: event.organization_id
        )

      {:error, reason} ->
        Logger.warning("Failed to transition stale event",
          live_event_id: event.id,
          org_id: event.organization_id,
          reason: inspect(reason)
        )
    end
  end
end
