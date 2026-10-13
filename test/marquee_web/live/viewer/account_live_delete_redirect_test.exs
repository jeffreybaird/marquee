defmodule MarqueeWeb.Viewer.AccountLiveDeleteRedirectTest do
  @moduledoc """
  E6: after a viewer deletes their account they land on their own
  organization's site. Without a tenant subdomain the tenant is only known
  from `?org=`, so the redirect must carry it (same rule as viewer logout in
  `ViewerSessionController`). On a tenant subdomain the plain `/` is kept,
  as covered by `AccountLiveTest`.
  """
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "without a subdomain, deletion redirects to the org's home with ?org=" do
    org = insert(:organization, slug: "apex-delete-org")
    viewer = insert(:viewer, organization: org)
    token = Marquee.Viewers.generate_viewer_session_token(viewer)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:host, "localhost")
      |> Phoenix.ConnTest.init_test_session(%{viewer_token: token})

    {:ok, view, _html} = live(conn, ~p"/account?org=#{org.slug}")

    view |> element(~s([data-test="account-delete-btn"])) |> render_click()

    flash = assert_redirect(view, "/?org=#{org.slug}")
    assert flash["info"] == "Your account has been deleted."
  end
end
