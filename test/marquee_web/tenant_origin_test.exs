defmodule MarqueeWeb.TenantOriginTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias Phoenix.Socket.Transport

  setup do
    keys = ["ORG_RESOLUTION", "PHX_HOST", "TENANT_HOST_PATTERN"]
    original = Map.new(keys, &{&1, System.get_env(&1)})
    System.put_env("ORG_RESOLUTION", "hostname")
    System.put_env("PHX_HOST", "marquee.jeffreybaird.com")
    System.delete_env("TENANT_HOST_PATTERN")

    on_exit(fn ->
      for {key, value} <- original do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  test "hostname opt-in configures the derived host pattern and same-origin WebSockets" do
    config = Config.Reader.read!("config/runtime.exs", env: :test)
    assert config[:marquee][:org_resolution] == :hostname
    assert config[:marquee][:tenant_host_pattern] == "{slug}-marquee.jeffreybaird.com"
    origin = config[:marquee][MarqueeWeb.Endpoint][:check_origin]
    assert origin == :conn

    ssl =
      Config.Reader.read!("config/prod.exs", env: :prod)[:marquee][MarqueeWeb.Endpoint][
        :force_ssl
      ]

    assert Keyword.has_key?(ssl, :host)
    assert ssl[:host] == nil

    for {request_origin, allowed?} <- [
          {"https://studio-marquee.jeffreybaird.com", true},
          {"https://other-marquee.jeffreybaird.com", false},
          {"https://evil.example", false}
        ] do
      conn =
        Plug.Test.conn(:get, "http://studio-marquee.jeffreybaird.com/live/websocket")
        |> put_req_header("x-forwarded-proto", "https")
        |> put_req_header("origin", request_origin)
        |> Plug.SSL.call(Plug.SSL.init(ssl))
        |> Transport.check_origin(__MODULE__, MarqueeWeb.Endpoint, check_origin: origin)

      assert conn.halted == not allowed?
      if not allowed?, do: assert(conn.status == 403)
    end

    conn =
      Plug.Test.conn(:get, "http://studio-marquee.jeffreybaird.com/login")
      |> Plug.SSL.call(Plug.SSL.init(ssl))

    assert get_resp_header(conn, "location") == ["https://studio-marquee.jeffreybaird.com/login"]
  end
end
