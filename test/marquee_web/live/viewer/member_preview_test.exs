defmodule MarqueeWeb.Viewer.MemberPreviewTest do
  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "admin preview persists across member pages and ends on return to admin", %{conn: conn} do
    org = insert(:organization)
    user = insert(:user)
    insert(:membership, organization: org, user: user, role: :admin)
    video = insert(:video, organization: org, mux_status: "ready")
    show = insert(:podcast_show, organization: org, published: true)

    conn = conn |> log_in_user(user) |> get("/?org=#{org.slug}&preview=member")
    assert get_session(conn, :member_preview_org_id) == org.id
    assert is_nil(get_session(conn, :viewer_token))
    preview_id = get_session(conn, :member_preview_viewer_id)
    assert is_nil(Marquee.Viewers.get_viewer_by_id(preview_id))

    for path <- [
          "/browse",
          "/watch/#{video.id}",
          "/watchlist",
          "/history",
          "/account",
          "/podcasts/#{show.slug}",
          "/"
        ] do
      {:ok, view, _} = live(recycle(conn), path)
      assert has_element?(view, "[data-test=impersonation-banner]", "Member preview")
    end

    {:ok, watch, _} = live(recycle(conn), "/watch/#{video.id}")
    render_click(watch, "playback_progress", %{"video_id" => video.id, "position" => 30})
    assert has_element?(watch, "[data-test=impersonation-banner]", "Member preview")

    events_conn = conn |> recycle() |> get("/events")
    assert html_response(events_conn, 200) =~ "Member preview"

    {:ok, account, _} = live(recycle(conn), "/account")
    refute has_element?(account, "[data-test=account-edit-btn]")
    render_click(account, "save", %{"viewer" => %{"display_name" => "Changed"}})
    assert has_element?(account, "[data-test=account-display-name]", "Member preview")

    conn = conn |> recycle() |> get("/admin")
    refute get_session(conn, :member_preview_org_id)
    assert {:error, {:redirect, %{to: "/login"}}} = live(recycle(conn), "/account")
  end

  test "unauthenticated requests cannot start preview", %{conn: conn} do
    org = insert(:organization)
    conn = get(conn, "/?org=#{org.slug}&preview=member")
    refute get_session(conn, :member_preview_org_id)
    assert {:error, {:redirect, %{to: "/login"}}} = live(recycle(conn), "/account")
  end

  test "owners and super admins can preview", %{conn: conn} do
    org = insert(:organization)
    owner = insert(:user)
    insert(:membership, organization: org, user: owner, role: :owner)

    for user <- [owner, insert(:super_admin)] do
      preview_conn = conn |> log_in_user(user) |> get("/?org=#{org.slug}&preview=member")
      {:ok, view, _} = live(recycle(preview_conn), "/account")
      assert has_element?(view, "[data-test=impersonation-banner]", "Member preview")
    end
  end

  test "preview cannot grant access to another tenant", %{conn: conn} do
    org = insert(:organization)
    other_org = insert(:organization)
    user = insert(:user)
    insert(:membership, organization: org, user: user, role: :admin)

    conn = conn |> log_in_user(user) |> get("/?org=#{org.slug}&preview=member")
    conn = conn |> recycle() |> get("/account?org=#{other_org.slug}")
    refute get_session(conn, :member_preview_org_id)
    assert redirected_to(conn) == "/login"
  end

  test "preview requires a current admin membership", %{conn: conn} do
    for role <- [:editor, :viewer_support] do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: role)
      preview_conn = conn |> log_in_user(user) |> get("/?org=#{org.slug}&preview=member")
      refute get_session(preview_conn, :member_preview_org_id)
      assert {:error, {:redirect, %{to: "/login"}}} = live(recycle(preview_conn), "/account")
    end
  end

  test "revoking admin access invalidates an existing preview", %{conn: conn} do
    org = insert(:organization)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :admin)
    conn = conn |> log_in_user(user) |> get("/?org=#{org.slug}&preview=member")
    Marquee.Repo.delete!(membership)
    assert {:error, {:redirect, %{to: "/login"}}} = live(recycle(conn), "/account")
  end
end
