defmodule Marquee.TenantDomains.ReadinessProbeTest do
  use ExUnit.Case, async: false

  alias Marquee.TenantDomains.ReadinessProbe
  alias Marquee.TenantDomains.ScriptedClients

  @host "studio-marquee.jeffreybaird.com"
  @target "192.0.2.25"
  @identity %{domain_id: "domain-123", generation: "generation-1"}

  setup do
    changes = [
      tenant_dns_resolver: Marquee.TenantDomains.ScriptedResolver,
      tenant_probe_req_options: [plug: {Req.Test, __MODULE__}, retry: false]
    ]

    original = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    start_supervised!(ScriptedClients)
    :ok
  end

  test "only correct public DNS plus HTTPS application identity is ready" do
    ScriptedClients.script(:resolve, [{:ok, %{a: [@target], aaaa: []}}])

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.scheme == :https
      assert conn.host == @host
      assert conn.request_path == "/.well-known/marquee-domain"
      assert conn.method == "GET"
      Req.Test.json(conn, Map.put(@identity, :hostname, @host))
    end)

    assert :ok = ReadinessProbe.check(@host, @target, @identity)
  end

  test "missing, mixed and conflicting DNS never initiates an HTTPS request" do
    for dns <- [
          {:error, :dns_pending},
          {:ok, %{a: [], aaaa: []}},
          {:ok, %{a: [@target, "192.0.2.99"], aaaa: []}},
          {:ok, %{a: [@target], aaaa: ["2001:db8::1"]}}
        ] do
      ScriptedClients.script(:resolve, [dns])

      Req.Test.stub(__MODULE__, fn _conn ->
        flunk("HTTPS must not be probed before DNS matches")
      end)

      assert {:error, :dns_pending} = ReadinessProbe.check(@host, @target, @identity)
    end
  end

  test "redirects, wrong application identity and untrusted TLS do not become ready" do
    for response <- [:redirect, :wrong_host, :wrong_generation, :wrong_domain, :tls_error] do
      ScriptedClients.script(:resolve, [{:ok, %{a: [@target], aaaa: []}}])

      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == @host

        case response do
          :redirect ->
            conn
            |> Plug.Conn.put_resp_header("location", "https://elsewhere.example/")
            |> Plug.Conn.send_resp(302, "")

          :wrong_host ->
            Req.Test.json(conn, Map.put(@identity, :hostname, "other.example"))

          :wrong_generation ->
            Req.Test.json(conn, %{
              hostname: @host,
              domain_id: @identity.domain_id,
              generation: "old"
            })

          :wrong_domain ->
            Req.Test.json(conn, %{
              hostname: @host,
              domain_id: "other",
              generation: @identity.generation
            })

          :tls_error ->
            Req.Test.transport_error(conn, {:tls_alert, {:unknown_ca, "untrusted"}})
        end
      end)

      assert {:error, :tls_pending} = ReadinessProbe.check(@host, @target, @identity)
    end
  end
end
