defmodule Marquee.Telemetry.ApplicationSetupTest do
  use ExUnit.Case, async: false

  alias MarqueeWeb.Plugs.TelemetryOrgPlug

  defmodule TenantRequest do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, _opts) do
      conn
      |> Plug.Conn.assign(:organization, %{id: "telemetry-test-org", slug: "telemetry-test"})
      |> TelemetryOrgPlug.call([])
      |> Plug.Conn.send_resp(200, "ok")
    end
  end

  test "application instrumentation exports tenant context on an incoming trace" do
    :ok = :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
    on_exit(fn -> :otel_simple_processor.set_exporter(:none) end)

    server = start_supervised!({Bandit, plug: TenantRequest, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    trace_hex = "4bf92f3577b34da6a3ce929d0e0e4736"
    trace_id = String.to_integer(trace_hex, 16)

    # Exercise Marquee's startup wiring and its tenant-enrichment plug together.
    # The test never installs instrumentation itself or asserts library span names.
    assert %{status: 200, body: "ok"} =
             Req.get!("http://127.0.0.1:#{port}/telemetry-test",
               headers: [{"traceparent", "00-#{trace_hex}-00f067aa0ba902b7-01"}],
               retry: false
             )

    assert_receive {:span, span} when elem(span, 1) == trace_id, 1_000
    attributes = span |> elem(10) |> :otel_attributes.map()
    assert attributes["marquee.org.id"] == "telemetry-test-org"
    assert attributes["marquee.org.slug"] == "telemetry-test"
  end
end
