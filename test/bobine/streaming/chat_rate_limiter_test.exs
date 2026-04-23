defmodule Bobine.Streaming.ChatRateLimiterTest do
  use ExUnit.Case, async: false

  alias Bobine.Streaming.ChatRateLimiter

  setup do
    ChatRateLimiter.clear()
    :ok
  end

  describe "check_and_record/3" do
    test "allows first message" do
      assert :ok = ChatRateLimiter.check_and_record("viewer-1", "event-1")
    end

    test "rate-limits second message within burst window (< 2 seconds)" do
      now = DateTime.utc_now()

      assert :ok = ChatRateLimiter.check_and_record("viewer-1", "event-1", now)

      # Same second — within burst window
      assert {:error, :rate_limited} =
               ChatRateLimiter.check_and_record("viewer-1", "event-1", now)
    end

    test "allows message after burst window expires (>= 2 seconds later)" do
      now = DateTime.utc_now()
      later = DateTime.add(now, 3, :second)

      assert :ok = ChatRateLimiter.check_and_record("viewer-1", "event-1", now)
      assert :ok = ChatRateLimiter.check_and_record("viewer-1", "event-1", later)
    end

    test "enforces sustained rate of 30 per 60 seconds" do
      now = DateTime.utc_now()

      # Send 30 messages, each 2 seconds apart (all within 60-second window)
      Enum.each(0..29, fn i ->
        ts = DateTime.add(now, i * 2, :second)
        assert :ok = ChatRateLimiter.check_and_record("viewer-2", "event-2", ts)
      end)

      # 31st message at t=62s — within 60s window? 60..0: yes, 60s total, oldest is at t=0
      # 31st message is at t=60s — oldest is t=0, still within 60s window
      # Let's send at t=60: the oldest entry (t=0) is exactly 60s ago, not less-than cutoff
      ts_31 = DateTime.add(now, 60, :second)

      assert {:error, :rate_limited} =
               ChatRateLimiter.check_and_record("viewer-2", "event-2", ts_31)
    end

    test "resets count after sustained window expires" do
      now = DateTime.utc_now()

      # Send 30 messages at t=0..58s
      Enum.each(0..29, fn i ->
        ts = DateTime.add(now, i * 2, :second)
        ChatRateLimiter.check_and_record("viewer-3", "event-3", ts)
      end)

      # At t=120s all previous messages are outside the 60s window
      future = DateTime.add(now, 120, :second)
      assert :ok = ChatRateLimiter.check_and_record("viewer-3", "event-3", future)
    end

    test "rate limits are per viewer+event pair — different viewer not affected" do
      now = DateTime.utc_now()

      # Viewer-A hits rate limit
      assert :ok = ChatRateLimiter.check_and_record("viewer-a", "event-x", now)

      assert {:error, :rate_limited} =
               ChatRateLimiter.check_and_record("viewer-a", "event-x", now)

      # Viewer-B on same event is unaffected
      assert :ok = ChatRateLimiter.check_and_record("viewer-b", "event-x", now)
    end

    test "rate limits are per viewer+event pair — different event not affected" do
      now = DateTime.utc_now()

      assert :ok = ChatRateLimiter.check_and_record("viewer-a", "event-1", now)

      assert {:error, :rate_limited} =
               ChatRateLimiter.check_and_record("viewer-a", "event-1", now)

      # Same viewer, different event: clean slate
      assert :ok = ChatRateLimiter.check_and_record("viewer-a", "event-2", now)
    end

    test "clear/0 resets all state" do
      now = DateTime.utc_now()

      assert :ok = ChatRateLimiter.check_and_record("viewer-clear", "event-clear", now)

      assert {:error, :rate_limited} =
               ChatRateLimiter.check_and_record("viewer-clear", "event-clear", now)

      ChatRateLimiter.clear()

      assert :ok = ChatRateLimiter.check_and_record("viewer-clear", "event-clear", now)
    end
  end
end
