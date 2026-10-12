defmodule Marquee.Buffers.EngagementBufferTest do
  @moduledoc """
  Contract for the buffered /shorts engagement writes (spec Revision 3, R3.2).

  Public API exercised here (the implementation must provide it):

    * `start_link(opts)` — `:name` (default `Marquee.Buffers.EngagementBuffer`)
      and `:flush_interval_ms` (default: app env `:engagement_buffer_flush_ms`,
      `:infinity` disables periodic flushes)
    * `push(entry)` / `push(server, entry)` — returns `:ok`
    * `flush()` / `flush(server)` — synchronous, returns `:ok`
    * entries: `{:completion, %{organization_id:, viewer_id:, video_id:}}` and
      `{:drop_off, attrs}` where `attrs` is what `Engagement.record_drop_off/1`
      accepts (atom or string keys)
    * flushes on terminate (traps exits)
  """

  # async: false — the buffer is a global process writing through the shared
  # sandbox connection, and telemetry handlers are global.
  use Marquee.DataCase, async: false

  alias Marquee.Buffers.{EngagementBuffer, ProgressBuffer}
  alias Marquee.Engagement
  alias Marquee.Engagement.{PlaybackDropOff, Progress, WatchHistory}

  setup do
    # Drain anything a previous test left behind before asserting on rows.
    :ok = EngagementBuffer.flush()
    ProgressBuffer.clear()

    org = insert(:organization)
    viewer = insert(:subscribed_viewer, organization: org)
    video = insert(:video, organization: org, mux_status: "ready", duration: 100.0)
    %{org: org, viewer: viewer, video: video}
  end

  defp completion(org, viewer, video),
    do: {:completion, %{organization_id: org.id, viewer_id: viewer.id, video_id: video.id}}

  defp drop_off(org, viewer, video, extra \\ %{}) do
    {:drop_off,
     Map.merge(
       %{
         organization_id: org.id,
         viewer_id: viewer.id,
         video_id: video.id,
         max_position: 42.0,
         video_duration: 100.0
       },
       extra
     )}
  end

  defp progress(org, viewer, video),
    do: Repo.get_by(Progress, organization_id: org.id, viewer_id: viewer.id, video_id: video.id)

  defp history_count(viewer, video) do
    Repo.aggregate(
      from(h in WatchHistory, where: h.viewer_id == ^viewer.id and h.video_id == ^video.id),
      :count
    )
  end

  defp drop_offs(viewer, video) do
    Repo.all(
      from d in PlaybackDropOff, where: d.viewer_id == ^viewer.id and d.video_id == ^video.id
    )
  end

  defp attach(event) do
    handler_id = "engagement-buffer-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn name, measurements, metadata, _ ->
          send(test_pid, {:telemetry, name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  describe "behaviour" do
    test "Marquee.Buffer defines push/1 and flush/0" do
      callbacks = Marquee.Buffer.behaviour_info(:callbacks)
      assert {:push, 1} in callbacks
      assert {:flush, 0} in callbacks
    end

    test "EngagementBuffer implements Marquee.Buffer" do
      behaviours = EngagementBuffer.module_info(:attributes) |> Keyword.get_values(:behaviour)
      assert Marquee.Buffer in List.flatten(behaviours)
    end

    test "the application supervises a buffer registered under the module name" do
      assert is_pid(Process.whereis(EngagementBuffer))
    end
  end

  describe "completions" do
    test "are not written until flush", ctx do
      assert :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))

      assert progress(ctx.org, ctx.viewer, ctx.video) == nil
      assert history_count(ctx.viewer, ctx.video) == 0

      assert :ok = EngagementBuffer.flush()

      assert %Progress{completed: true} = progress(ctx.org, ctx.viewer, ctx.video)
      assert history_count(ctx.viewer, ctx.video) == 1
    end

    test "flush applies the mark_completed side effects", ctx do
      Marquee.Events.subscribe(ctx.org.id)
      attach([:marquee, :video, :completed])
      ProgressBuffer.update_viewer(ctx.org.id, ctx.viewer.id, ctx.video.id, 55.0, 100.0)

      :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.flush()

      video_id = ctx.video.id
      org_id = ctx.org.id

      assert_receive {:marquee_event, {:video_completed, %{video: %{id: ^video_id}}}, _}

      assert_receive {:telemetry, [:marquee, :video, :completed], _,
                      %{video_id: ^video_id, org_id: ^org_id}}

      assert ProgressBuffer.get_viewer(ctx.org.id, ctx.viewer.id, ctx.video.id) == nil
    end

    test "an existing progress row is marked completed rather than duplicated", ctx do
      insert(:progress,
        organization: ctx.org,
        user: nil,
        viewer: ctx.viewer,
        video: ctx.video,
        position: 30.0
      )

      :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.flush()

      rows =
        Repo.all(
          from p in Progress, where: p.viewer_id == ^ctx.viewer.id and p.video_id == ^ctx.video.id
        )

      assert [%Progress{completed: true}] = rows
    end

    test "duplicates for the same org, viewer and video in one window have one effect", ctx do
      Marquee.Events.subscribe(ctx.org.id)
      attach([:marquee, :video, :completed])

      for _ <- 1..3, do: :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.flush()

      video_id = ctx.video.id
      assert_receive {:marquee_event, {:video_completed, %{video: %{id: ^video_id}}}, _}
      refute_receive {:marquee_event, {:video_completed, %{video: %{id: ^video_id}}}, _}, 100
      assert_receive {:telemetry, [:marquee, :video, :completed], _, %{video_id: ^video_id}}
      refute_receive {:telemetry, [:marquee, :video, :completed], _, %{video_id: ^video_id}}, 100
      assert history_count(ctx.viewer, ctx.video) == 1
    end

    test "different viewers of the same video are not deduplicated", ctx do
      other_viewer = insert(:subscribed_viewer, organization: ctx.org)

      :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.push(completion(ctx.org, other_viewer, ctx.video))
      :ok = EngagementBuffer.flush()

      assert %Progress{completed: true} = progress(ctx.org, ctx.viewer, ctx.video)
      assert %Progress{completed: true} = progress(ctx.org, other_viewer, ctx.video)
    end
  end

  describe "drop-offs" do
    test "are not written until flush", ctx do
      assert :ok = EngagementBuffer.push(drop_off(ctx.org, ctx.viewer, ctx.video))
      assert drop_offs(ctx.viewer, ctx.video) == []

      :ok = EngagementBuffer.flush()

      assert [%PlaybackDropOff{organization_id: org_id}] = drop_offs(ctx.viewer, ctx.video)
      assert org_id == ctx.org.id
    end

    test "normalise exactly like record_drop_off/1", ctx do
      direct_viewer = insert(:subscribed_viewer, organization: ctx.org)

      for {extra, label} <- [
            {%{max_position: 42.0}, "float"},
            {%{max_position: 42}, "integer"},
            {%{max_position: nil}, "nil"}
          ] do
        {:drop_off, attrs} = drop_off(ctx.org, ctx.viewer, ctx.video, extra)
        direct_attrs = %{attrs | viewer_id: direct_viewer.id}

        {:ok, direct} = Engagement.record_drop_off(direct_attrs)
        :ok = EngagementBuffer.push({:drop_off, attrs})
        :ok = EngagementBuffer.flush()

        [buffered] = drop_offs(ctx.viewer, ctx.video)

        assert buffered.bucket == direct.bucket, label
        assert buffered.max_position == direct.max_position, label
        assert buffered.video_duration == direct.video_duration, label
        assert buffered.counted_at == nil, label
        assert abs(DateTime.diff(buffered.left_at, direct.left_at)) <= 5, label

        Repo.delete_all(from d in PlaybackDropOff, where: d.video_id == ^ctx.video.id)
      end
    end

    test "accept string keys and string positions like record_drop_off/1", ctx do
      :ok =
        EngagementBuffer.push(
          {:drop_off,
           %{
             "organization_id" => ctx.org.id,
             "viewer_id" => ctx.viewer.id,
             "video_id" => ctx.video.id,
             "max_position" => "42.5",
             "video_duration" => 100.0
           }}
        )

      :ok = EngagementBuffer.flush()

      assert [drop] = drop_offs(ctx.viewer, ctx.video)
      assert drop.max_position == 42.5
      assert drop.bucket == PlaybackDropOff.bucket_for(42.5)
    end

    test "an explicit left_at is preserved", ctx do
      left_at = ~U[2026-01-02 03:04:05Z]
      :ok = EngagementBuffer.push(drop_off(ctx.org, ctx.viewer, ctx.video, %{left_at: left_at}))
      :ok = EngagementBuffer.flush()

      assert [%{left_at: ^left_at}] = drop_offs(ctx.viewer, ctx.video)
    end

    test "emit the drop-off metric per row", ctx do
      attach([:marquee, :playback, :drop_off_recorded])
      :ok = EngagementBuffer.push(drop_off(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.flush()

      video_id = ctx.video.id

      assert_receive {:telemetry, [:marquee, :playback, :drop_off_recorded], _,
                      %{video_id: ^video_id}}
    end

    test "invalid entries are dropped without crashing or blocking valid ones", ctx do
      pid = Process.whereis(EngagementBuffer)
      valid_video = insert(:video, organization: ctx.org, mux_status: "ready")

      # Missing video_id fails validation; an unknown video id fails the FK.
      :ok =
        EngagementBuffer.push(
          {:drop_off, %{organization_id: ctx.org.id, viewer_id: ctx.viewer.id, max_position: 5.0}}
        )

      :ok = EngagementBuffer.push(drop_off(ctx.org, ctx.viewer, %{id: Ecto.UUID.generate()}))
      :ok = EngagementBuffer.push(drop_off(ctx.org, ctx.viewer, valid_video))

      assert :ok = EngagementBuffer.flush()

      assert Process.whereis(EngagementBuffer) == pid
      assert [_] = drop_offs(ctx.viewer, valid_video)

      # The buffer keeps working afterwards.
      :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.flush()
      assert %Progress{completed: true} = progress(ctx.org, ctx.viewer, ctx.video)
    end
  end

  describe "tenant isolation" do
    test "entries from two orgs flush independently and keep their tenant ids", ctx do
      org_b = insert(:organization)
      viewer_b = insert(:subscribed_viewer, organization: org_b)
      video_b = insert(:video, organization: org_b, mux_status: "ready", duration: 100.0)

      :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.push(completion(org_b, viewer_b, video_b))
      :ok = EngagementBuffer.push(drop_off(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.push(drop_off(org_b, viewer_b, video_b))
      :ok = EngagementBuffer.flush()

      assert %Progress{completed: true, organization_id: org_a_id} =
               progress(ctx.org, ctx.viewer, ctx.video)

      assert org_a_id == ctx.org.id
      assert %Progress{completed: true} = progress(org_b, viewer_b, video_b)
      assert [%{organization_id: a}] = drop_offs(ctx.viewer, ctx.video)
      assert [%{organization_id: b}] = drop_offs(viewer_b, video_b)
      assert {a, b} == {ctx.org.id, org_b.id}
    end

    test "a failing org's entries do not prevent another org's entries", ctx do
      org_b = insert(:organization)
      viewer_b = insert(:subscribed_viewer, organization: org_b)
      video_b = insert(:video, organization: org_b, mux_status: "ready", duration: 100.0)

      # Org A's batch references a video that does not exist (FK violation).
      :ok = EngagementBuffer.push(drop_off(ctx.org, ctx.viewer, %{id: Ecto.UUID.generate()}))
      :ok = EngagementBuffer.push(drop_off(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.push(drop_off(org_b, viewer_b, video_b))

      assert :ok = EngagementBuffer.flush()

      assert [_] = drop_offs(viewer_b, video_b)
    end
  end

  describe "invalid completions" do
    test "cross-org or unknown ids and malformed entries write nothing and do not block valid ones",
         ctx do
      pid = Process.whereis(EngagementBuffer)
      org_b = insert(:organization)
      video_b = insert(:video, organization: org_b, mux_status: "ready", duration: 100.0)
      unknown_viewer_id = Ecto.UUID.generate()

      # Org B's video under org A's ids, and an unknown viewer.
      :ok =
        EngagementBuffer.push(
          {:completion,
           %{organization_id: ctx.org.id, viewer_id: ctx.viewer.id, video_id: video_b.id}}
        )

      :ok =
        EngagementBuffer.push(
          {:completion,
           %{organization_id: ctx.org.id, viewer_id: unknown_viewer_id, video_id: ctx.video.id}}
        )

      # Malformed and unknown entries.
      :ok = EngagementBuffer.push({:completion, %{}})
      :ok = EngagementBuffer.push({:bogus, 1})

      # A valid completion alongside.
      :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))

      assert :ok = EngagementBuffer.flush()
      assert Process.whereis(EngagementBuffer) == pid

      refute Repo.exists?(from p in Progress, where: p.video_id == ^video_b.id)
      refute Repo.exists?(from h in WatchHistory, where: h.video_id == ^video_b.id)
      refute Repo.exists?(from p in Progress, where: p.viewer_id == ^unknown_viewer_id)
      refute Repo.exists?(from h in WatchHistory, where: h.viewer_id == ^unknown_viewer_id)

      assert %Progress{completed: true} = progress(ctx.org, ctx.viewer, ctx.video)
      assert history_count(ctx.viewer, ctx.video) == 1
    end
  end

  describe "lifecycle" do
    test "flushes pending entries on terminate", ctx do
      name = :"engagement_buffer_terminate_#{System.unique_integer([:positive])}"

      start_supervised!({EngagementBuffer, name: name, flush_interval_ms: :infinity}, id: name)

      :ok = EngagementBuffer.push(name, completion(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.push(name, drop_off(ctx.org, ctx.viewer, ctx.video))
      assert progress(ctx.org, ctx.viewer, ctx.video) == nil

      :ok = stop_supervised!(name)

      assert %Progress{completed: true} = progress(ctx.org, ctx.viewer, ctx.video)
      assert [_] = drop_offs(ctx.viewer, ctx.video)
    end

    test "flushes periodically on the configured interval", ctx do
      name = :"engagement_buffer_periodic_#{System.unique_integer([:positive])}"
      Marquee.Events.subscribe(ctx.org.id)

      start_supervised!({EngagementBuffer, name: name, flush_interval_ms: 20}, id: name)
      :ok = EngagementBuffer.push(name, completion(ctx.org, ctx.viewer, ctx.video))

      # No explicit flush: the timer must deliver the completion event.
      video_id = ctx.video.id
      assert_receive {:marquee_event, {:video_completed, %{video: %{id: ^video_id}}}, _}, 2_000
      _ = :sys.get_state(name)

      assert %Progress{completed: true} = progress(ctx.org, ctx.viewer, ctx.video)
    end

    test "a named instance does not flush the global buffer's entries", ctx do
      name = :"engagement_buffer_isolated_#{System.unique_integer([:positive])}"
      start_supervised!({EngagementBuffer, name: name, flush_interval_ms: :infinity}, id: name)

      :ok = EngagementBuffer.push(completion(ctx.org, ctx.viewer, ctx.video))
      :ok = EngagementBuffer.flush(name)
      assert progress(ctx.org, ctx.viewer, ctx.video) == nil

      :ok = EngagementBuffer.flush()
      assert %Progress{completed: true} = progress(ctx.org, ctx.viewer, ctx.video)
    end
  end
end
