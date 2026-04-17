defmodule BobineWeb.RouterRateLimitTest do
  # Not async: shared ETS table in BobineWeb.Plugs.RateLimit.
  use BobineWeb.ConnCase, async: false

  alias BobineWeb.Plugs.RateLimit

  setup do
    # Global `rate_limit_disabled: true` in config/test.exs keeps the
    # plug quiet for the broader suite. These tests exercise router
    # wiring of the plug, so re-enable it for the duration.
    Application.put_env(:bobine, :rate_limit_disabled, false)
    on_exit(fn -> Application.put_env(:bobine, :rate_limit_disabled, true) end)
    # Ensure the plug's ETS table is clean so counters don't bleed between
    # cases (e.g. webhook tests that run in the same file).
    RateLimit.reset()
    :ok
  end

  describe "webhook rate limiting" do
    @describetag :capture_log
    test "blocks /webhooks/mux after the per-IP limit is hit", %{conn: conn} do
      Application.put_env(:bobine, :mux_webhook_secret, "test-secret")
      on_exit(fn -> Application.delete_env(:bobine, :mux_webhook_secret) end)

      # Burn the 500/min budget for this IP with cheap invalid-signature hits.
      for _ <- 1..500 do
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/mux", "{}")
      end

      blocked =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/mux", "{}")

      assert blocked.status == 429
      assert Plug.Conn.get_resp_header(blocked, "retry-after") == ["60"]
    end
  end

  describe "auth rate limiting" do
    test "blocks POST /users/log-in after 10/min", %{conn: conn} do
      for _ <- 1..10 do
        post(conn, "/users/log-in", %{"user" => %{"email" => "x@x", "password" => "wrong"}})
      end

      blocked =
        post(conn, "/users/log-in", %{"user" => %{"email" => "x@x", "password" => "wrong"}})

      assert blocked.status == 429
    end
  end
end
