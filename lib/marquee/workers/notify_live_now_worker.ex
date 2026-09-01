defmodule Marquee.Workers.NotifyLiveNowWorker do
  @moduledoc """
  Oban worker that sends "event is live now" emails to all viewers
  who set a reminder for a live event.

  Processes reminder viewers in paginated batches so no single job
  performs an unbounded DB read. Per-viewer email failures are logged
  but do not fail the job — partial delivery is preferred over retrying
  all viewers when only one email bounces.

  After a successful send, marks the reminder's `notified_at` so the
  viewer is not emailed again on retry.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Marquee.Accounts.Organization
  alias Marquee.Repo
  alias Marquee.Streaming
  alias Marquee.Streaming.LiveEvent
  alias Marquee.Streaming.LiveEventNotifier
  alias Marquee.Streaming.LiveEventReminder

  @impl true
  def perform(%Oban.Job{args: %{"live_event_id" => event_id, "organization_id" => org_id} = args}) do
    Marquee.Otel.extract_trace_context(args["trace_context"])

    Logger.metadata(
      worker: "NotifyLiveNowWorker",
      org_id: org_id,
      live_event_id: event_id
    )

    Tracer.with_span "marquee.worker.notify_live_now" do
      Tracer.set_attributes([
        {"marquee.org.id", org_id},
        {"marquee.live_event.id", event_id}
      ])

      case load_event_and_org(event_id, org_id) do
        {:ok, event, org} ->
          send_notifications_for_event(event, org)

        {:error, :event_not_found} ->
          Logger.warning("NotifyLiveNowWorker: live event not found",
            live_event_id: event_id,
            org_id: org_id
          )

          {:ok, :skipped}

        {:error, :org_not_found} ->
          Logger.warning("NotifyLiveNowWorker: organization not found",
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

  defp send_notifications_for_event(event, org) do
    if event.status == "live" do
      process_all_reminder_pages(event, org)
    else
      Logger.info(
        "NotifyLiveNowWorker: event not live, skipping notifications",
        live_event_id: event.id,
        org_id: event.organization_id,
        status: event.status
      )

      {:ok, :skipped}
    end
  end

  defp process_all_reminder_pages(event, org) do
    process_reminder_page(event, org, 1, 0)
  end

  defp process_reminder_page(event, org, page, sent_count) do
    %{results: reminders, total_pages: total_pages} =
      Streaming.list_reminder_viewers(event, page: page, per_page: 50)

    new_count =
      Enum.reduce(reminders, sent_count, fn reminder, acc ->
        notify_reminder_viewer(reminder, event, org)
        acc + 1
      end)

    if page < total_pages do
      process_reminder_page(event, org, page + 1, new_count)
    else
      Logger.info("NotifyLiveNowWorker: sent live-now emails",
        live_event_id: event.id,
        org_id: event.organization_id,
        count: new_count
      )

      {:ok, :sent}
    end
  end

  defp notify_reminder_viewer(%LiveEventReminder{viewer: viewer} = reminder, event, org) do
    case LiveEventNotifier.deliver_live_now(viewer, event, org) do
      {:ok, _email} ->
        mark_reminder_notified(reminder)

      {:error, reason} ->
        Logger.warning("NotifyLiveNowWorker: failed to deliver email",
          viewer_id: viewer.id,
          live_event_id: event.id,
          org_id: event.organization_id,
          reason: inspect(reason)
        )
    end
  end

  defp mark_reminder_notified(%LiveEventReminder{} = reminder) do
    reminder
    |> LiveEventReminder.notified_changeset(%{
      notified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> case do
      {:ok, _updated} ->
        :ok

      {:error, changeset} ->
        Logger.warning("NotifyLiveNowWorker: failed to mark reminder notified",
          reminder_id: reminder.id,
          errors: inspect(changeset.errors)
        )
    end
  end
end
