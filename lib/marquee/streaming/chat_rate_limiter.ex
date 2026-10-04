defmodule Marquee.Streaming.ChatRateLimiter do
  @moduledoc """
  ETS-backed GenServer that enforces per-viewer, per-event chat rate limits.

  Rules:
    * No more than 1 message per 2 seconds (burst protection).
    * No more than 30 messages per 60 seconds (sustained-rate cap).

  Timestamps older than 60 seconds are pruned on every check, so the ETS
  table stays bounded even for long-lived events.

  This module is intentionally free of Repo calls — it is purely in-memory.
  """

  use GenServer

  @table :chat_rate_limiter

  # 2-second burst window
  @burst_window_seconds 2
  @burst_max 1

  # 60-second sustained window
  @sustained_window_seconds 60
  @sustained_max 30

  ## ---------------------------------------------------------------------------
  ## Public API
  ## ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks whether the viewer may send a message to the given event and, if
  allowed, records the current timestamp.

  Returns `:ok` when the send is permitted, or `{:error, :rate_limited}` when
  either rate limit is exceeded.

  Accepts an optional `now` parameter (a `DateTime`) for deterministic testing
  without sleeps.

  ## Examples

      iex> Marquee.Streaming.ChatRateLimiter.check_and_record(Ecto.UUID.generate(), Ecto.UUID.generate())
      :ok
  """
  def check_and_record(viewer_id, event_id, now \\ nil) do
    now = now || DateTime.utc_now()
    key = {viewer_id, event_id}
    cutoff = DateTime.add(now, -@sustained_window_seconds, :second)

    existing =
      case :ets.lookup(@table, key) do
        [{^key, timestamps}] -> timestamps
        [] -> []
      end

    # Prune timestamps outside the sustained window (inclusive boundary).
    recent = Enum.filter(existing, fn ts -> DateTime.compare(ts, cutoff) != :lt end)

    # Burst check: any message strictly within last @burst_window_seconds?
    # Messages at exactly the boundary (== burst_cutoff) are NOT counted —
    # the viewer has waited the full window and may send again.
    burst_cutoff = DateTime.add(now, -@burst_window_seconds, :second)

    burst_recent =
      Enum.filter(recent, fn ts -> DateTime.compare(ts, burst_cutoff) == :gt end)

    cond do
      length(burst_recent) >= @burst_max ->
        {:error, :rate_limited}

      length(recent) >= @sustained_max ->
        {:error, :rate_limited}

      true ->
        :ets.insert(@table, {key, [now | recent]})
        :ok
    end
  end

  @doc """
  Clears all rate-limit state. Useful in tests.
  """
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  ## ---------------------------------------------------------------------------
  ## GenServer callbacks
  ## ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end
end
