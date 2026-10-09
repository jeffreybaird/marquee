defmodule MarqueeWeb.Plugs.MemberPreviewTest do
  use MarqueeWeb.ConnCase, async: true

  alias Marquee.Accounts.Scope
  alias Marquee.Branding
  alias Marquee.Branding.Theme
  alias MarqueeWeb.Plugs.MemberPreview

  defp draft do
    %{
      theme: %Theme{background: "#123456"},
      accent_color_base: "#ABCDEF",
      display_font: "Playfair Display"
    }
  end

  defp scope_for(org, role) do
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: role)
    Scope.for_user(user) |> Scope.with_organization(org, membership)
  end

  # Drives the plug directly so the session rules can be asserted without the
  # rest of the router pipeline. `assigns` mirrors what SetOrganization and
  # UserAuth leave on the conn before MemberPreview runs.
  defp run_plug(path, session, scope, org) do
    :get
    |> Plug.Test.conn(path)
    |> Plug.Test.init_test_session(session)
    |> Plug.Conn.fetch_query_params()
    |> Plug.Conn.assign(:current_scope, scope)
    |> Plug.Conn.assign(:organization, org)
    |> MemberPreview.call(MemberPreview.init([]))
  end

  describe "theme_preview/3" do
    test "returns the stored draft for an authorized admin" do
      org = insert(:organization)
      scope = scope_for(org, :admin)
      preview_id = Ecto.UUID.generate()
      :ok = Branding.put_theme_preview(org, preview_id, draft())

      assert MemberPreview.theme_preview(%{"appearance_preview_id" => preview_id}, scope, org) ==
               draft()
    end

    test "returns nil when the session carries no preview id" do
      org = insert(:organization)
      scope = scope_for(org, :admin)

      assert MemberPreview.theme_preview(%{}, scope, org) == nil
      assert MemberPreview.theme_preview(%{"appearance_preview_id" => nil}, scope, org) == nil
    end

    test "returns nil when no draft is stored for the preview id" do
      org = insert(:organization)
      scope = scope_for(org, :admin)

      assert MemberPreview.theme_preview(
               %{"appearance_preview_id" => Ecto.UUID.generate()},
               scope,
               org
             ) == nil
    end

    test "returns nil for an operator below the admin role" do
      org = insert(:organization)
      scope = scope_for(org, :editor)
      preview_id = Ecto.UUID.generate()
      :ok = Branding.put_theme_preview(org, preview_id, draft())

      assert MemberPreview.theme_preview(%{"appearance_preview_id" => preview_id}, scope, org) ==
               nil
    end

    test "returns nil without an organization or scope" do
      org = insert(:organization)
      preview_id = Ecto.UUID.generate()
      :ok = Branding.put_theme_preview(org, preview_id, draft())

      assert MemberPreview.theme_preview(%{"appearance_preview_id" => preview_id}, nil, org) ==
               nil

      assert MemberPreview.theme_preview(
               %{"appearance_preview_id" => preview_id},
               scope_for(org, :admin),
               nil
             ) == nil
    end
  end

  describe "call/2 on /admin/appearance" do
    test "starts an appearance preview session for an admin" do
      org = insert(:organization)
      scope = scope_for(org, :admin)

      conn = run_plug("/admin/appearance", %{}, scope, org)

      assert is_binary(get_session(conn, :appearance_preview_id))
      assert get_session(conn, :member_preview_org_id) == org.id
      assert is_binary(get_session(conn, :member_preview_viewer_id))
    end

    test "keeps an existing appearance preview id across repeat visits" do
      org = insert(:organization)
      scope = scope_for(org, :admin)
      existing = Ecto.UUID.generate()

      conn =
        run_plug(
          "/admin/appearance",
          %{appearance_preview_id: existing, member_preview_org_id: org.id},
          scope,
          org
        )

      assert get_session(conn, :appearance_preview_id) == existing
      assert get_session(conn, :member_preview_org_id) == org.id
    end

    test "keeps the existing member preview identity for the same organization" do
      org = insert(:organization)
      scope = scope_for(org, :admin)
      viewer_id = Ecto.UUID.generate()

      conn =
        run_plug(
          "/admin/appearance",
          %{member_preview_org_id: org.id, member_preview_viewer_id: viewer_id},
          scope,
          org
        )

      assert get_session(conn, :member_preview_viewer_id) == viewer_id
    end

    test "does not start a preview session for an operator below admin" do
      org = insert(:organization)
      scope = scope_for(org, :editor)

      conn = run_plug("/admin/appearance", %{}, scope, org)

      refute get_session(conn, :appearance_preview_id)
      refute get_session(conn, :member_preview_org_id)
      refute get_session(conn, :member_preview_viewer_id)
    end
  end

  describe "call/2 on other admin paths" do
    test "clears the appearance preview along with the member preview keys" do
      org = insert(:organization)
      scope = scope_for(org, :admin)

      conn =
        run_plug(
          "/admin",
          %{
            appearance_preview_id: Ecto.UUID.generate(),
            member_preview_org_id: org.id,
            member_preview_viewer_id: Ecto.UUID.generate()
          },
          scope,
          org
        )

      refute get_session(conn, :appearance_preview_id)
      refute get_session(conn, :member_preview_org_id)
      refute get_session(conn, :member_preview_viewer_id)
    end
  end

  describe "call/2 on viewer paths" do
    test "assigns the draft as theme_preview when the session holds a valid one" do
      org = insert(:organization)
      scope = scope_for(org, :admin)
      preview_id = Ecto.UUID.generate()
      :ok = Branding.put_theme_preview(org, preview_id, draft())

      conn =
        run_plug(
          "/browse",
          %{
            appearance_preview_id: preview_id,
            member_preview_org_id: org.id,
            member_preview_viewer_id: Ecto.UUID.generate()
          },
          scope,
          org
        )

      assert conn.assigns.theme_preview == draft()
      assert get_session(conn, :appearance_preview_id) == preview_id
    end

    test "leaves theme_preview unset when the session has no draft" do
      org = insert(:organization)
      scope = scope_for(org, :admin)

      conn = run_plug("/browse", %{}, scope, org)

      refute conn.assigns[:theme_preview]
    end

    test "?preview=member keeps the appearance preview id" do
      org = insert(:organization)
      scope = scope_for(org, :admin)
      preview_id = Ecto.UUID.generate()

      conn =
        run_plug(
          "/?preview=member",
          %{appearance_preview_id: preview_id},
          scope,
          org
        )

      assert get_session(conn, :appearance_preview_id) == preview_id
      assert get_session(conn, :member_preview_org_id) == org.id
    end

    test "clears every preview key when the preview targets another organization" do
      org = insert(:organization)
      other_org = insert(:organization)
      scope = scope_for(org, :admin)
      preview_id = Ecto.UUID.generate()
      :ok = Branding.put_theme_preview(org, preview_id, draft())

      conn =
        run_plug(
          "/browse",
          %{
            appearance_preview_id: preview_id,
            member_preview_org_id: org.id,
            member_preview_viewer_id: Ecto.UUID.generate()
          },
          scope,
          other_org
        )

      refute get_session(conn, :appearance_preview_id)
      refute get_session(conn, :member_preview_org_id)
      refute get_session(conn, :member_preview_viewer_id)
      refute conn.assigns[:theme_preview]
    end

    test "clears every preview key when the operator is no longer authorized" do
      org = insert(:organization)
      scope = scope_for(org, :editor)
      preview_id = Ecto.UUID.generate()
      :ok = Branding.put_theme_preview(org, preview_id, draft())

      conn =
        run_plug(
          "/browse",
          %{
            appearance_preview_id: preview_id,
            member_preview_org_id: org.id,
            member_preview_viewer_id: Ecto.UUID.generate()
          },
          scope,
          org
        )

      refute get_session(conn, :appearance_preview_id)
      refute get_session(conn, :member_preview_org_id)
      refute get_session(conn, :member_preview_viewer_id)
      refute conn.assigns[:theme_preview]
    end
  end
end
