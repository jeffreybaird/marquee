defmodule Marquee.Streaming.LiveEventNotifierHostnameTest do
  use Marquee.DataCase, async: false

  alias Marquee.Streaming.LiveEventNotifier

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

  describe "deliver_live_now/3 watch URL with hostname resolution" do
    test "uses the slug subdomain of the base host even when it contains .fly.dev" do
      org = insert(:organization, slug: "acme-tv", custom_domain: nil)
      event = insert(:live_event, organization: org, slug: "big-stream")
      viewer = insert(:viewer, organization: org)

      assert {:ok, email} = LiveEventNotifier.deliver_live_now(viewer, event, org)

      assert email.text_body =~ "https://acme-tv.marquee-app.fly.dev/events/big-stream"
    end

    test "custom domain still takes precedence over the slug subdomain" do
      org = insert(:organization, slug: "acme-tv", custom_domain: "watch.acme.example")
      event = insert(:live_event, organization: org, slug: "big-stream")
      viewer = insert(:viewer, organization: org)

      assert {:ok, email} = LiveEventNotifier.deliver_live_now(viewer, event, org)

      assert email.text_body =~ "https://watch.acme.example/events/big-stream"
    end
  end
end
