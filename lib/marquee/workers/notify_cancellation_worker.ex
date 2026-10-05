defmodule Marquee.Workers.NotifyCancellationWorker do
  @moduledoc """
  Oban worker that sends "event canceled" emails when a live event is canceled.

  For pay-per-view events, notifies both ticket holders (who paid) and viewers
  with reminders. For all other access types, notifies only reminder viewers.
  Viewer IDs are deduplicated so no viewer receives two emails.

  Per-viewer failures are logged but do not fail the job so that a single
  bounced address does not block notification of all other viewers.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Marquee.Accounts.Organization
  alias Marquee.Repo
  alias Marquee.Streaming
  alias Marquee.Streaming.LiveEvent
  alias Marquee.Streaming.LiveEventNotifier

  @impl true
  def perform(%Oban.Job{args: %{"live_event_id" => event_id, "organization_id" => org_id} = args}) do
    Marquee.Otel.extract_trace_context(args["trace_context"])

    Logger.metadata(
      worker: "NotifyCancellationWorker",
      org_id: org_id,
      live_event_id: event_id
    )

    Tracer.with_span "marquee.worker.notify_cancellation" do
      Tracer.set_attributes([
        {"marquee.org.id", org_id},
        {"marquee.live_event.id", event_id}
      ])

      case load_event_and_org(event_id, org_id) do
        {:ok, event, org} ->
          with :ok <-
                 Marquee.AdminDemo.worker_permission(
                   Marquee.AdminDemo.external_resource(LiveEvent, event.id, org.id)
                 ) do
            send_cancellation_notifications(event, org)
          end

        {:error, :event_not_found} ->
          Logger.warning("NotifyCancellationWorker: live event not found",
            live_event_id: event_id,
            org_id: org_id
          )

          {:ok, :skipped}

        {:error, :org_not_found} ->
          Logger.warning("NotifyCancellationWorker: organization not found",
            org_id: org_id
          )

          {:ok, :skipped}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp load_event_and_org(event_id, org_id) do
    org = Repo.get(Organization, org_id)
    event = Repo.get(LiveEvent, event_id)

    cond do
      is_nil(org) -> {:error, :org_not_found}
      is_nil(event) -> {:error, :event_not_found}
      true -> {:ok, event, org}
    end
  end

  defp send_cancellation_notifications(event, org) do
    notified_viewer_ids = collect_and_notify_ticket_holders(event, org, MapSet.new())
    _final_ids = collect_and_notify_reminder_viewers(event, org, notified_viewer_ids)

    Logger.info("NotifyCancellationWorker: cancellation notifications sent",
      live_event_id: event.id,
      org_id: event.organization_id
    )

    {:ok, :sent}
  end

  # For PPV events, notify unrefunded ticket holders first
  defp collect_and_notify_ticket_holders(
         %LiveEvent{access_type: "pay_per_view"} = event,
         org,
         seen_ids
       ) do
    collect_ticket_holder_pages(event, org, seen_ids, 1)
  end

  defp collect_and_notify_ticket_holders(_event, _org, seen_ids), do: seen_ids

  defp collect_ticket_holder_pages(event, org, seen_ids, page) do
    %{results: tickets, total_pages: total_pages} =
      Streaming.list_unrefunded_ticket_viewers(event, page: page, per_page: 50)

    new_seen =
      Enum.reduce(tickets, seen_ids, fn ticket, acc ->
        viewer = ticket.viewer
        viewer_id = viewer.id

        if MapSet.member?(acc, viewer_id) do
          acc
        else
          deliver_cancellation_email(viewer, event, org)
          MapSet.put(acc, viewer_id)
        end
      end)

    if page < total_pages do
      collect_ticket_holder_pages(event, org, new_seen, page + 1)
    else
      new_seen
    end
  end

  defp collect_and_notify_reminder_viewers(event, org, seen_ids) do
    collect_reminder_pages(event, org, seen_ids, 1)
  end

  defp collect_reminder_pages(event, org, seen_ids, page) do
    %{results: reminders, total_pages: total_pages} =
      Streaming.list_reminder_viewers(event, page: page, per_page: 50)

    new_seen =
      Enum.reduce(reminders, seen_ids, fn reminder, acc ->
        viewer = reminder.viewer
        viewer_id = viewer.id

        if MapSet.member?(acc, viewer_id) do
          acc
        else
          deliver_cancellation_email(viewer, event, org)
          MapSet.put(acc, viewer_id)
        end
      end)

    if page < total_pages do
      collect_reminder_pages(event, org, new_seen, page + 1)
    else
      new_seen
    end
  end

  defp deliver_cancellation_email(viewer, event, org) do
    case LiveEventNotifier.deliver_cancellation(viewer, event, org) do
      {:ok, _email} ->
        :ok

      {:error, reason} ->
        Logger.warning("NotifyCancellationWorker: failed to deliver email",
          viewer_id: viewer.id,
          live_event_id: event.id,
          org_id: event.organization_id,
          reason: inspect(reason)
        )
    end
  end
end
