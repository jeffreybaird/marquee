defmodule BobineWeb.Plugs.SetRequestContextTest do
  use BobineWeb.ConnCase, async: true

  alias Bobine.RequestContext

  describe "SetRequestContext plug" do
    test "sets request context with request_id, ip, and user_agent", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "TestBrowser/1.0")
        |> get("/users/log-in")

      ctx = RequestContext.current()
      assert ctx.ip == "127.0.0.1"
      assert ctx.user_agent == "TestBrowser/1.0"
      assert is_nil(ctx.request_id) or is_binary(ctx.request_id)
      assert conn.status == 200
    end

    test "context is accessible via RequestContext.current/0 within the request", %{conn: conn} do
      _conn = get(conn, "/users/log-in")

      ctx = RequestContext.current()
      assert is_map(ctx)
      assert Map.has_key?(ctx, :ip)
      assert Map.has_key?(ctx, :user_agent)
      assert Map.has_key?(ctx, :scope)
    end

    test "returns nil when no context has been set" do
      # In a fresh process, no context should be set
      task = Task.async(fn -> RequestContext.current() end)
      assert Task.await(task) == nil
    end
  end
end
