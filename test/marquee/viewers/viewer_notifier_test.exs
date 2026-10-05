defmodule Marquee.Viewers.ViewerNotifierTest do
  use Marquee.DataCase, async: false

  alias Marquee.Viewers.ViewerNotifier

  @keys [:org_resolution, :tenant_host_pattern, :tenant_domain_provisioning, MarqueeWeb.Endpoint]

  setup do
    original = Map.new(@keys, &{&1, Application.fetch_env(:marquee, &1)})

    on_exit(fn ->
      for {key, value} <- original do
        case value do
          {:ok, value} -> Application.put_env(:marquee, key, value)
          :error -> Application.delete_env(:marquee, key)
        end
      end
    end)

    Application.put_env(:marquee, :org_resolution, :hostname)
    Application.delete_env(:marquee, :tenant_host_pattern)
    Application.put_env(:marquee, :tenant_domain_provisioning, enabled: false)
    endpoint = Application.get_env(:marquee, MarqueeWeb.Endpoint, [])

    Application.put_env(
      :marquee,
      MarqueeWeb.Endpoint,
      Keyword.put(endpoint, :url, host: "marquee-app.fly.dev", scheme: "https", port: 443)
    )

    :ok
  end

  describe "deliver_magic_link/3 with hostname resolution" do
    test "uses the slug subdomain of the base host even when it contains .fly.dev" do
      org = insert(:organization, slug: "acme-tv", custom_domain: nil)
      viewer = insert(:viewer, organization: org)

      assert {:ok, email} = ViewerNotifier.deliver_magic_link(viewer, "test-token", org)

      assert email.text_body =~ "https://acme-tv.marquee-app.fly.dev/magic-link/test-token"
    end

    test "custom domain still takes precedence over the slug subdomain" do
      org = insert(:organization, slug: "acme-tv", custom_domain: "watch.acme.example")
      viewer = insert(:viewer, organization: org)

      assert {:ok, email} = ViewerNotifier.deliver_magic_link(viewer, "test-token", org)

      assert email.text_body =~ "https://watch.acme.example/magic-link/test-token"
    end
  end
end
