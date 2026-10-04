defmodule MarqueeFeatures.Steps.TenantHostname do
  @moduledoc """
  Host routing scenarios exercise the HTTP boundary directly. Synthetic production
  hosts do not need public DNS or browser JavaScript to verify tenant selection.
  """
  use Cucumberex.DSL

  import ExUnit.Assertions
  import Marquee.Factory
  import Plug.Conn

  alias MarqueeWeb.Plugs.SetOrganization

  given_("tenant hostname routing is configured", fn world ->
    Map.merge(world, %{hostname_org: insert(:organization), hostname_other: insert(:organization)})
  end)

  when_("I request the studio hostname with another studio query parameter", fn world ->
    conn =
      configured(fn ->
        request(
          "#{world.hostname_org.slug}-marquee.jeffreybaird.com",
          "/login?org=#{world.hostname_other.slug}"
        )
        |> SetOrganization.call([])
      end)

    Map.put(world, :hostname_conn, conn)
  end)

  then_("hostname routing selects the requested studio", fn world ->
    assert world.hostname_conn.assigns.organization.id == world.hostname_org.id
    world
  end)

  when_("I request the old studio bookmark", fn world ->
    conn =
      configured(fn ->
        request("marquee.jeffreybaird.com", "/login?org=#{world.hostname_org.slug}&ref=bookmark")
        |> SetOrganization.call([])
      end)

    Map.put(world, :hostname_conn, conn)
  end)

  then_("hostname routing redirects to the studio hostname and preserves the page", fn world ->
    assert world.hostname_conn.status == 302
    [location] = get_resp_header(world.hostname_conn, "location")
    uri = URI.parse(location)
    assert uri.host == "#{world.hostname_org.slug}-marquee.jeffreybaird.com"
    assert uri.path == "/login"
    assert URI.decode_query(uri.query) == %{"ref" => "bookmark"}
    world
  end)

  when_("I request an unrelated hostname with a remembered studio", fn world ->
    conn =
      configured(fn ->
        request("#{world.hostname_org.slug}.unrelated.example", "/login")
        |> put_session(:organization_id, world.hostname_org.id)
        |> SetOrganization.call([])
      end)

    Map.put(world, :hostname_conn, conn)
  end)

  then_("hostname routing returns organization not found", fn world ->
    assert world.hostname_conn.status == 404
    assert world.hostname_conn.halted
    world
  end)

  when_("I generate a studio login URL", fn world ->
    url =
      configured(fn ->
        MarqueeWeb.OrgURL.org_url("https://marquee.jeffreybaird.com/login", world.hostname_org)
      end)

    Map.put(world, :hostname_url, url)
  end)

  then_(
    "the login URL uses the studio hostname without an organization query parameter",
    fn world ->
      assert world.hostname_url ==
               "https://#{world.hostname_org.slug}-marquee.jeffreybaird.com/login"

      world
    end
  )

  defp request(host, path) do
    Plug.Test.conn(:get, path)
    |> Map.put(:host, host)
    |> Plug.Test.init_test_session(%{})
  end

  defp configured(fun) do
    keys = [:org_resolution, :tenant_host_pattern, MarqueeWeb.Endpoint]
    original = Map.new(keys, &{&1, Application.fetch_env(:marquee, &1)})
    Application.put_env(:marquee, :org_resolution, :hostname)
    Application.put_env(:marquee, :tenant_host_pattern, "{slug}-marquee.jeffreybaird.com")
    endpoint = Application.fetch_env!(:marquee, MarqueeWeb.Endpoint)

    Application.put_env(
      :marquee,
      MarqueeWeb.Endpoint,
      Keyword.put(endpoint, :url, host: "marquee.jeffreybaird.com", scheme: "https", port: 443)
    )

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
