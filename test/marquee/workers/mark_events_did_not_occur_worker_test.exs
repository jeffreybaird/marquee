defmodule Marquee.Workers.MarkEventsDidNotOccurWorkerTest do
  use Marquee.DataCase, async: true
  use Oban.Testing, repo: Marquee.Repo

  alias Marquee.Repo
  alias Marquee.Streaming.LiveEvent
  alias Marquee.Workers.MarkEventsDidNotOccurWorker

  defp stale_time,
    do: DateTime.add(DateTime.utc_now(), -31 * 60, :second) |> DateTime.truncate(:second)

  defp recent_time,
    do: DateTime.add(DateTime.utc_now(), -10 * 60, :second) |> DateTime.truncate(:second)

  defp future_time,
    do: DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

  describe "perform/1" do
    test "transitions a stale scheduled event to did_not_occur" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          scheduled_start_at: stale_time()
        )

      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      updated = Repo.get!(LiveEvent, event.id)
      assert updated.status == "did_not_occur"
    end

    test "leaves a recent scheduled event unchanged" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          scheduled_start_at: recent_time()
        )

      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      unchanged = Repo.get!(LiveEvent, event.id)
      assert unchanged.status == "scheduled"
    end

    test "leaves an already-ended event unchanged" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "ended",
          scheduled_start_at: stale_time()
        )

      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      unchanged = Repo.get!(LiveEvent, event.id)
      assert unchanged.status == "ended"
    end

    test "leaves a canceled event unchanged" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "canceled",
          scheduled_start_at: stale_time()
        )

      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      unchanged = Repo.get!(LiveEvent, event.id)
      assert unchanged.status == "canceled"
    end

    test "transitions stale events from multiple orgs" do
      org_a = insert(:organization)
      org_b = insert(:organization)

      event_a =
        insert(:live_event,
          organization: org_a,
          status: "scheduled",
          scheduled_start_at: stale_time()
        )

      event_b =
        insert(:live_event,
          organization: org_b,
          status: "scheduled",
          scheduled_start_at: stale_time()
        )

      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      assert Repo.get!(LiveEvent, event_a.id).status == "did_not_occur"
      assert Repo.get!(LiveEvent, event_b.id).status == "did_not_occur"
    end

    test "does not transition soft-deleted events" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          scheduled_start_at: stale_time(),
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      unchanged = Repo.get!(LiveEvent, event.id)
      assert unchanged.status == "scheduled"
    end

    test "is idempotent — second run is a no-op for already-transitioned event" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          scheduled_start_at: stale_time()
        )

      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      updated = Repo.get!(LiveEvent, event.id)
      assert updated.status == "did_not_occur"

      # Run again — event is now "did_not_occur" and not in the stale query
      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      still_same = Repo.get!(LiveEvent, event.id)
      assert still_same.status == "did_not_occur"
    end

    test "does not affect future-scheduled events" do
      org = insert(:organization)

      event =
        insert(:live_event,
          organization: org,
          status: "scheduled",
          scheduled_start_at: future_time()
        )

      assert :ok = perform_job(MarkEventsDidNotOccurWorker, %{})

      unchanged = Repo.get!(LiveEvent, event.id)
      assert unchanged.status == "scheduled"
    end
  end
end
