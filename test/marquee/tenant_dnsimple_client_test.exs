defmodule Marquee.TenantDomains.DNSimpleClientTest do
  use ExUnit.Case, async: false

  alias Marquee.TenantDomains.DNSimpleClient

  @host "studio-marquee.jeffreybaird.com"
  @target "192.0.2.25"

  setup do
    changes = [
      tenant_domain_provisioning: [
        enabled: true,
        zone: "jeffreybaird.com",
        account_id: "123",
        api_token: "test-token",
        target_ipv4: @target,
        host_pattern: "{slug}-marquee.jeffreybaird.com"
      ],
      tenant_dns_req_options: [plug: {Req.Test, __MODULE__}, retry: false]
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

    :ok
  end

  test "adopts exactly matching A on a later page without creating another record" do
    parent = self()

    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.method == "GET"
      assert conn.request_path == "/v2/123/zones/jeffreybaird.com/records"
      assert conn.query_params["name"] == "studio-marquee"
      refute Map.has_key?(conn.query_params, "type")
      send(parent, {:page, conn.query_params["page"] || "1"})

      if conn.query_params["page"] == "2" do
        Req.Test.json(conn, page([record(42, "A", @target)], 2, 2))
      else
        Req.Test.json(conn, page([%{record(9, "A", "192.0.2.99") | name: "unrelated"}], 1, 2))
      end
    end)

    assert {:ok, %{id: 42}} = DNSimpleClient.ensure_record(@host, @target, "job-key")
    assert_received {:page, "1"}
    assert_received {:page, "2"}
  end

  test "creates only an absent exact-name A after checking every page" do
    parent = self()

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.method do
        "GET" ->
          conn = Plug.Conn.fetch_query_params(conn)
          number = if conn.query_params["page"] == "2", do: 2, else: 1
          send(parent, {:listed, number})
          Req.Test.json(conn, page([], number, 2))

        "POST" ->
          assert_received {:listed, 1}
          assert_received {:listed, 2}
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["name"] == "studio-marquee"
          assert payload["type"] == "A"
          assert payload["content"] == @target
          send(parent, :created)
          Req.Test.json(conn, %{data: record(43, "A", @target)})
      end
    end)

    assert {:ok, %{id: 43}} = DNSimpleClient.ensure_record(@host, @target, "job-key")
    assert_received :created
    refute_received :created
  end

  test "mismatched A, duplicate A, AAAA and CNAME conflicts never mutate DNS" do
    conflicts = [
      [record(1, "A", "192.0.2.99")],
      [record(1, "A", @target), record(2, "A", @target)],
      [record(1, "AAAA", "2001:db8::1")],
      [record(1, "CNAME", "elsewhere.example")],
      [record(1, "A", @target), record(2, "AAAA", "2001:db8::1")]
    ]

    for records <- conflicts do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "GET"
        Req.Test.json(conn, page(records, 1, 1))
      end)

      assert {:error, :dns_conflict} = DNSimpleClient.ensure_record(@host, @target, "job-key")
    end
  end

  test "a lost create response triggers relisting and exact adoption instead of another POST" do
    {:ok, state} = Agent.start_link(fn -> %{posts: 0, gets: 0} end)
    on_exit(fn -> if Process.alive?(state), do: Agent.stop(state) end)

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.method do
        "GET" ->
          snapshot = Agent.get_and_update(state, &{&1, Map.update!(&1, :gets, fn n -> n + 1 end)})
          rows = if snapshot.posts == 0, do: [], else: [record(44, "A", @target)]
          Req.Test.json(conn, page(rows, 1, 1))

        "POST" ->
          Agent.update(state, &Map.update!(&1, :posts, fn n -> n + 1 end))
          Req.Test.transport_error(conn, :timeout)
      end
    end)

    assert {:ok, %{id: 44}} = DNSimpleClient.ensure_record(@host, @target, "job-key")
    assert %{posts: 1, gets: 2} = Agent.get(state, & &1)
  end

  test "failed listing never attempts a write and returns a sanitized retryable error" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"

      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{message: "private test-token response"})
    end)

    assert {:error, reason} = DNSimpleClient.ensure_record(@host, @target, "job-key")
    assert reason in [:dns_unavailable, :configuration]
    refute inspect(reason) =~ "test-token"
  end

  defp record(id, type, content),
    do: %{id: id, name: "studio-marquee", type: type, content: content}

  defp page(data, current, total),
    do: %{
      data: data,
      pagination: %{
        current_page: current,
        total_pages: total,
        per_page: 100,
        total_entries: length(data)
      }
    }
end
