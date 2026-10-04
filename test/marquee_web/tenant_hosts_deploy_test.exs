defmodule MarqueeWeb.TenantHostsDeployTest do
  use ExUnit.Case, async: true

  @script Path.expand("../../deploy/tenant-hosts.sh", __DIR__)

  test "explicit hosts include the platform and each tenant without a wildcard" do
    assert {output, 0} = render("marquee.jeffreybaird.com", "the-workshop,another-studio")

    assert String.trim(output) ==
             "marquee.jeffreybaird.com, the-workshop-marquee.jeffreybaird.com, another-studio-marquee.jeffreybaird.com"
  end

  test "empty tenant list preserves existing single site deployment" do
    assert {output, 0} = render("marquee.jeffreybaird.com", "")
    assert String.trim(output) == "marquee.jeffreybaird.com"
  end

  test "invalid tenant labels and Caddy injection are rejected" do
    for slug <- [
          "-bad",
          "bad-",
          "bad.name",
          "bad name",
          "bad\n}",
          "bad,",
          ",bad",
          "bad,,next",
          "UPPER",
          String.duplicate("a", 57)
        ] do
      assert {_output, status} = render("marquee.jeffreybaird.com", slug)
      assert status != 0, slug
    end
  end

  test "invalid platform domains are rejected" do
    for domain <- [
          "",
          "https://marquee.example.com",
          "bad\n}",
          "*.example.com",
          "-bad.example.com",
          "bad..example.com"
        ] do
      assert {_output, status} = render(domain, "studio")
      assert status != 0, domain
    end
  end

  defp render(domain, slugs) do
    System.cmd("bash", [@script],
      env: [{"DOMAIN", domain}, {"TENANT_SLUGS", slugs}],
      stderr_to_stdout: true
    )
  end
end
