defmodule MarqueeWeb.Viewer.SubscriberDemoDiscoveryTest do
  use MarqueeWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Marquee.Viewers

  test "marketing entry and session use a feature-enabled tenant's current slug" do
    org = insert(:organization, slug: "renamed-studio", features: %{"subscriber_demo" => true})
    insert(:video, organization: org, published: true, mux_status: "ready", duration: 180.0)
    {:ok, home, _} = live(build_conn(), "/")
    assert has_element?(home, "[data-test=subscriber-demo-entry][href='/?org=renamed-studio']")
    conn = build_conn() |> Map.put(:host, "renamed-studio.localhost") |> post("/demo/subscriber")
    assert redirected_to(conn) == "/"
    viewer = Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token))
    assert viewer.organization_id == org.id
    other = insert(:organization, slug: "other-studio", features: %{"subscriber_demo" => true})
    insert(:video, organization: other, published: true, mux_status: "ready", duration: 180.0)

    other_conn =
      conn |> recycle() |> Map.put(:host, "other-studio.localhost") |> post("/demo/subscriber")

    other_viewer = Viewers.get_viewer_by_session_token(get_session(other_conn, :viewer_token))
    assert other_viewer.organization_id == other.id
    assert other_viewer.id != viewer.id
  end

  test "a familiar slug cannot enable a disabled tenant" do
    insert(:organization, slug: "the-workshop", features: %{})
    {:ok, home, _} = live(build_conn(), "/")
    refute has_element?(home, "[data-test=subscriber-demo-entry]")
    conn = build_conn() |> Map.put(:host, "the-workshop.localhost") |> post("/demo/subscriber")
    assert conn.status == 403
    refute get_session(conn, :viewer_token)
  end
end
