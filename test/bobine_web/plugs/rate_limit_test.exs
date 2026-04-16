defmodule BobineWeb.Plugs.RateLimitTest do
  # Not async: the plug uses a shared named ETS table.
  use BobineWeb.ConnCase, async: false

  alias BobineWeb.Plugs.RateLimit

  doctest BobineWeb.Plugs.RateLimit

  setup do
    RateLimit.reset()
    :ok
  end

  defp make_conn(remote_ip \\ {127, 0, 0, 1}) do
    build_conn(:get, "/anywhere")
    |> Map.put(:remote_ip, remote_ip)
  end

  describe "init/1" do
    test "returns the opts unchanged when :bucket is provided" do
      assert RateLimit.init(bucket: :test, limit: 1) == [bucket: :test, limit: 1]
    end

    test "raises when :bucket is missing" do
      assert_raise KeyError, fn -> RateLimit.init([]) end
    end
  end

  describe "call/2 under limit" do
    test "allows the first request" do
      conn = RateLimit.call(make_conn(), RateLimit.init(bucket: :b_allow, limit: 3))
      refute conn.halted
    end

    test "allows requests until the limit is reached" do
      opts = RateLimit.init(bucket: :b_under, limit: 3)

      for _ <- 1..3 do
        conn = RateLimit.call(make_conn(), opts)
        refute conn.halted
      end
    end
  end

  describe "call/2 over limit" do
    test "halts with 429 and retry-after once the limit is exceeded" do
      opts = RateLimit.init(bucket: :b_over, limit: 2, period: :timer.minutes(1))

      RateLimit.call(make_conn(), opts)
      RateLimit.call(make_conn(), opts)
      blocked = RateLimit.call(make_conn(), opts)

      assert blocked.halted
      assert blocked.status == 429
      assert Plug.Conn.get_resp_header(blocked, "retry-after") == ["60"]
    end

    test "isolates counters per bucket" do
      opts_a = RateLimit.init(bucket: :b_iso_a, limit: 1)
      opts_b = RateLimit.init(bucket: :b_iso_b, limit: 1)

      refute RateLimit.call(make_conn(), opts_a).halted
      # Different bucket — the first request in :b_iso_b is still fresh.
      refute RateLimit.call(make_conn(), opts_b).halted
    end

    test "isolates counters per IP when keyed by :ip" do
      opts = RateLimit.init(bucket: :b_ips, limit: 1, key: :ip)

      refute RateLimit.call(make_conn({1, 1, 1, 1}), opts).halted
      # New IP, same bucket — its own counter.
      refute RateLimit.call(make_conn({2, 2, 2, 2}), opts).halted
      # Original IP, second hit — over limit.
      assert RateLimit.call(make_conn({1, 1, 1, 1}), opts).halted
    end
  end

  describe "call/2 window refresh" do
    test "restarts the counter once the period elapses" do
      opts = RateLimit.init(bucket: :b_refresh, limit: 1, period: 50)

      refute RateLimit.call(make_conn(), opts).halted
      assert RateLimit.call(make_conn(), opts).halted

      Process.sleep(75)

      # Window has expired — the next request is allowed again.
      refute RateLimit.call(make_conn(), opts).halted
    end
  end

  describe "keying strategies" do
    test ":organization_id uses conn.assigns.organization.id when present" do
      opts = RateLimit.init(bucket: :b_org, limit: 1, key: :organization_id)
      org_conn = make_conn() |> Plug.Conn.assign(:organization, %{id: "org-1"})

      refute RateLimit.call(org_conn, opts).halted
      # Same org → same counter → second hit is blocked.
      assert RateLimit.call(org_conn, opts).halted

      # Different org → own counter.
      other = make_conn() |> Plug.Conn.assign(:organization, %{id: "org-2"})
      refute RateLimit.call(other, opts).halted
    end

    test ":user_id uses conn.assigns.current_scope.user.id when present" do
      opts = RateLimit.init(bucket: :b_user, limit: 1, key: :user_id)

      scope = %{user: %{id: "user-1"}}
      user_conn = make_conn() |> Plug.Conn.assign(:current_scope, scope)

      refute RateLimit.call(user_conn, opts).halted
      assert RateLimit.call(user_conn, opts).halted
    end

    test ":organization_id falls back to IP when organization is missing" do
      opts = RateLimit.init(bucket: :b_fallback, limit: 1, key: :organization_id)

      refute RateLimit.call(make_conn({10, 0, 0, 1}), opts).halted
      assert RateLimit.call(make_conn({10, 0, 0, 1}), opts).halted
      # A different IP gets its own bucket because org is still missing.
      refute RateLimit.call(make_conn({10, 0, 0, 2}), opts).halted
    end
  end
end
