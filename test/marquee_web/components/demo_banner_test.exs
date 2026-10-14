defmodule MarqueeWeb.Components.DemoBannerTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MarqueeWeb.Components.AdminDemo

  test "subscriber demo exposes an accessible dismiss button and keeps mobile navigation outside the banner" do
    org = insert(:organization, features: %{"subscriber_demo" => true})
    insert(:video, organization: org, published: true, mux_status: "ready")
    conn = build_conn() |> Map.put(:host, "#{org.slug}.localhost") |> post("/demo/subscriber")
    assert redirected_to(conn) == "/"

    viewer = Marquee.Viewers.get_viewer_by_session_token(get_session(conn, :viewer_token))
    assert Marquee.SubscriberDemo.demo_viewer?(viewer)
    assert viewer.organization_id == org.id
    {:ok, view, _html} = live(recycle(conn), "/")

    assert has_element?(
             view,
             "[data-test=subscriber-demo-banner] button[data-test=subscriber-demo-dismiss][type=button][aria-label='Dismiss demo banner']"
           )

    assert has_element?(view, "[data-test=subscriber-demo-mobile-nav] a[href='/browse']")
    assert has_element?(view, "[data-test=subscriber-demo-mobile-nav] a[href='/watchlist']")

    refute has_element?(
             view,
             "[data-test=subscriber-demo-banner] [data-test=subscriber-demo-mobile-nav]"
           )
  end

  test "ordinary viewers have no demo dismissal control" do
    org = insert(:organization)
    viewer = insert(:viewer, organization: org)
    {:ok, view, _html} = live(conn_for_viewer(viewer), "/")
    refute has_element?(view, "[data-test=subscriber-demo-dismiss]")
  end

  test "admin demo exposes a separate accessible dismissal action without removing reset and exit" do
    org = build(:organization, demo_kind: :admin_sandbox)
    html = render_component(&AdminDemo.bar/1, organization: org)
    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query(
             "button[data-test=admin-demo-dismiss][type=button][aria-label='Dismiss demo banner']"
           )
           |> LazyHTML.to_tree()
           |> Enum.any?()

    for selector <- ["[data-test=admin-demo-reset]", "[data-test=admin-demo-exit]"] do
      assert document |> LazyHTML.query(selector) |> LazyHTML.to_tree() |> Enum.any?()
    end
  end

  test "ordinary organizations have no admin demo dismissal control" do
    html =
      render_component(&AdminDemo.bar/1, organization: build(:organization))

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("[data-test=admin-demo-dismiss]")
           |> LazyHTML.to_tree() == []
  end
end
