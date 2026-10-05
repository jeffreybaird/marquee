defmodule MarqueeFeatures.Steps.TenantProvisioning do
  @moduledoc "Readiness rollout scenarios at the real HTTP routing boundary."
  use Cucumberex.DSL

  import ExUnit.Assertions
  import Marquee.Factory
  import Phoenix.ConnTest

  alias Marquee.TenantDomains

  @endpoint MarqueeWeb.Endpoint
  @platform "marquee.jeffreybaird.com"

  given_("a studio is enrolled for hostname provisioning", fn world ->
    org = insert(:organization)

    {:ok, domain} =
      configured(fn ->
        Oban.Testing.with_testing_mode(:manual, fn ->
          TenantDomains.request_provisioning(org, source: :existing_organization)
        end)
      end)

    Map.merge(world, %{provisioning_org: org, provisioning_domain: domain})
  end)

  given_("its hostname has completed DNS and HTTPS readiness", fn world ->
    domain =
      world.provisioning_domain
      |> Ecto.Changeset.change(
        status: :ready,
        dns_record_id: "fixture-record",
        ready_at: DateTime.utc_now()
      )
      |> Marquee.Repo.update!()

    Map.put(world, :provisioning_domain, domain)
  end)

  when_("I open its existing platform login link", fn world ->
    conn =
      configured(fn ->
        build_conn()
        |> Map.put(:host, @platform)
        |> get("/login?org=#{world.provisioning_org.slug}")
      end)

    Map.put(world, :provisioning_conn, conn)
  end)

  then_("the platform still shows that studio login", fn world ->
    assert html_response(world.provisioning_conn, 200) =~ world.provisioning_org.name
    world
  end)

  then_("the platform redirects to its ready hostname login", fn world ->
    assert redirected_to(world.provisioning_conn) ==
             "https://#{world.provisioning_domain.hostname}/login"

    world
  end)

  defp configured(fun) do
    pattern = "{slug}-marquee.jeffreybaird.com"
    endpoint = Application.fetch_env!(:marquee, MarqueeWeb.Endpoint)

    changes = [
      {:tenant_domain_provisioning,
       [
         enabled: true,
         zone: "jeffreybaird.com",
         account_id: "123",
         api_token: "test-token",
         target_ipv4: "192.0.2.25",
         host_pattern: pattern
       ]},
      {:tenant_host_pattern, pattern},
      {:org_resolution, :query_param},
      {MarqueeWeb.Endpoint,
       Keyword.put(endpoint, :url, host: @platform, scheme: "https", port: 443)}
    ]

    original = Map.new(changes, fn {key, _} -> {key, Application.fetch_env(:marquee, key)} end)
    for {key, value} <- changes, do: Application.put_env(:marquee, key, value)

    try do
      fun.()
    after
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end
  end
end
