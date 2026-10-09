defmodule MarqueeWeb.Viewer.AppearancePreviewTest do
  @moduledoc """
  Issue #21 — unsaved appearance changes must survive navigating from the
  `/admin/appearance` preview into the real viewer site and back.

  Opening the editor starts a draft session. Explicit preview navigation lets
  the operator browse the viewer site as a read-only member preview that
  renders the *draft* theme, with a banner back to the editor. Returning to
  the editor restores the draft. Any other admin page, or saving, ends it.
  """

  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Branding
  alias Marquee.Branding.Theme
  alias Plug.Conn.Query

  @draft_background "#123456"
  @draft_accent "#ABCDEF"
  @draft_font "Playfair Display"
  @saved_font "DM Serif Display"

  @form "form[phx-submit='save_appearance']"
  @draft_params %{
    organization: %{accent_color_base: "#ABCDEF", display_font: "Playfair Display"},
    theme: %{background: "#123456"}
  }

  # An org with a saved theme, a saved display font, an admin operator, and a
  # catalog (hero slide + curated row) so `/` and `/browse` render real cards
  # and `/watch/:id` resolves a playable video.
  defp setup_org(_context) do
    org = insert(:organization, display_font: @saved_font)
    user = insert(:user)
    membership = insert(:membership, organization: org, user: user, role: :admin)

    {:ok, saved_theme} =
      Branding.create_theme(Theme.preset_attrs("midnight") |> Map.put(:organization_id, org.id))

    video =
      insert(:video,
        organization: org,
        title: "Preview Feature",
        mux_status: "ready",
        published: true
      )

    hero_row = insert(:hero_row, organization: org)
    insert(:hero_slide, organization: org, row: hero_row, video: video, position: 0)

    row =
      insert(:row,
        organization: org,
        title: "Preview Row",
        source_type: :curated,
        visible: true,
        position: 1
      )

    insert(:row_item, organization: org, row: row, video: video, position: 0)

    %{org: org, user: user, membership: membership, saved_theme: saved_theme, video: video}
  end

  # Opens the editor (dead render through the plug pipeline, which starts the
  # preview session), connects to it and streams a draft through the form.
  defp open_editor_with_draft(conn, user, org) do
    conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")
    {:ok, view, _html} = live(recycle(conn), "/admin/appearance")

    view
    |> form(@form, @draft_params)
    |> render_change()

    # Precondition for every caller: the edit must have been stored as a
    # draft, otherwise the negative-path tests below could pass trivially.
    assert Branding.get_theme_preview(org, get_session(conn, :appearance_preview_id)),
           "expected validate_appearance to store a draft for the session's preview id"

    {conn |> recycle() |> get("/browse?preview=member"), view}
  end

  # The inline `style` attribute of the viewer root element, read precisely
  # rather than scanning the whole subtree.
  defp sv_root_style(view) do
    [style] =
      view
      |> element("[data-test=sv-root]")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-test=sv-root]")
      |> LazyHTML.attribute("style")

    style
  end

  defp assert_draft_rendered(view) do
    style = sv_root_style(view)
    assert style =~ "--sv-bg-primary: #{@draft_background}"
    assert style =~ "--color-accent: #{@draft_accent}"
    assert has_element?(view, "[data-test=impersonation-banner]", "Member preview")

    assert has_element?(
             view,
             "[data-test=appearance-preview-notice]",
             "Showing unsaved appearance changes."
           )

    assert has_element?(
             view,
             "[data-test=appearance-preview-editor-link][href='/admin/appearance']",
             "Back to editor"
           )
  end

  defp refute_draft_rendered(view) do
    refute sv_root_style(view) =~ @draft_background
    refute has_element?(view, "[data-test=appearance-preview-notice]")
    refute has_element?(view, "[data-test=appearance-preview-editor-link]")
  end

  describe "opening the appearance editor" do
    setup :setup_org

    test "starts a draft session without replacing the viewer identity", %{
      conn: conn,
      user: user,
      org: org
    } do
      conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")

      assert is_binary(get_session(conn, :appearance_preview_id))
      refute get_session(conn, :member_preview_org_id)
      refute get_session(conn, :member_preview_viewer_id)
      refute html_response(conn, 200) =~ "appearance-preview-restored"
    end

    test "keeps the same preview id on a repeat visit", %{conn: conn, user: user, org: org} do
      conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")
      preview_id = get_session(conn, :appearance_preview_id)

      again = conn |> recycle() |> get("/admin/appearance")
      assert get_session(again, :appearance_preview_id) == preview_id
    end

    test "an editor-role operator gets no appearance preview session", %{conn: conn, org: org} do
      editor = insert(:user)
      insert(:membership, organization: org, user: editor, role: :editor)

      conn = conn |> log_in_user(editor) |> get("/admin/appearance?org=#{org.slug}")

      refute get_session(conn, :appearance_preview_id)
      refute get_session(conn, :member_preview_org_id)
    end
  end

  describe "browsing the viewer site with an unsaved draft" do
    setup :setup_org

    test "live viewer pages render the draft theme with a banner back to the editor", %{
      conn: conn,
      user: user,
      org: org,
      video: video
    } do
      {conn, _view} = open_editor_with_draft(conn, user, org)

      for path <- ["/", "/browse", "/watch/#{video.id}"] do
        {:ok, view, _html} = live(recycle(conn), path)
        assert_draft_rendered(view)
      end
    end

    test "the dead-rendered events page renders the draft theme and notice", %{
      conn: conn,
      user: user,
      org: org
    } do
      {conn, _view} = open_editor_with_draft(conn, user, org)

      html = conn |> recycle() |> get("/events") |> html_response(200)

      assert html =~ "--sv-bg-primary: #{@draft_background}"
      assert html =~ "--color-accent: #{@draft_accent}"
      assert html =~ ~s(data-test="appearance-preview-notice")
      assert html =~ "Member preview"
    end

    test "the root layout loads the draft display font instead of the saved one", %{
      conn: conn,
      user: user,
      org: org
    } do
      {conn, _view} = open_editor_with_draft(conn, user, org)

      html = conn |> recycle() |> get("/") |> html_response(200)

      assert html =~ "fonts.googleapis.com/css2?family=Playfair+Display"
      refute html =~ "family=DM+Serif+Display"
    end

    test "a real viewer never sees another session's draft", %{
      conn: conn,
      user: user,
      org: org
    } do
      {_conn, _view} = open_editor_with_draft(conn, user, org)
      viewer = insert(:viewer, organization: org)

      {:ok, view, _html} = live(conn_for_viewer(viewer), "/")

      refute_draft_rendered(view)
    end

    test "a draft for one organization never reaches another organization's site", %{
      conn: conn,
      user: user,
      org: org
    } do
      other_org = insert(:organization)
      insert(:membership, organization: other_org, user: user, role: :admin)
      {conn, _view} = open_editor_with_draft(conn, user, org)

      other = conn |> recycle() |> get("/browse?org=#{other_org.slug}")

      assert get_session(other, :appearance_preview_id) ==
               get_session(conn, :appearance_preview_id)

      refute get_session(other, :member_preview_org_id)
      refute other.assigns[:theme_preview]

      # `/browse` is public, so the other org's site renders and must not
      # carry the draft.
      html = html_response(other, 200)
      refute html =~ @draft_background
      refute html =~ "appearance-preview-notice"

      {:ok, editor, _} = live(recycle(other), "/admin/appearance?org=#{org.slug}")
      assert has_element?(editor, "[data-test=appearance-preview-restored]")

      assert has_element?(
               editor,
               "[data-test=color-input-background] input[value='#{@draft_background}']"
             )
    end
  end

  describe "returning to the editor" do
    setup :setup_org

    test "restores the draft into the forms and the preview frame", %{
      conn: conn,
      user: user,
      org: org
    } do
      {conn, _view} = open_editor_with_draft(conn, user, org)

      {:ok, editor, _html} = live(recycle(conn), "/admin/appearance")

      assert has_element?(
               editor,
               "[data-test=appearance-preview-restored]",
               "Restored your unsaved appearance changes."
             )

      assert has_element?(
               editor,
               "[data-test=color-input-background] input[type=text][value='#{@draft_background}']"
             )

      assert has_element?(
               editor,
               "[data-test=color-input-accent_color_base] input[type=text][value='#{@draft_accent}']"
             )

      assert has_element?(
               editor,
               "select[name='organization[display_font]'] option[value='#{@draft_font}'][selected]"
             )

      # Read the decoded `style` attribute: raw HTML escapes the quotes
      # around the font name, so a string match on the markup cannot see it.
      [frame_style] =
        editor
        |> element("[data-test=preview-frame]")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-test=preview-frame] > .sv-root")
        |> LazyHTML.attribute("style")

      assert frame_style =~ "--sv-bg-primary: #{@draft_background}"
      assert frame_style =~ "--color-accent: #{@draft_accent}"
      assert frame_style =~ "--font-display: '#{@draft_font}', Georgia, serif"
    end
  end

  describe "ending the draft" do
    setup :setup_org

    test "visiting another admin page clears the session and the viewer site shows the saved theme",
         %{conn: conn, user: user, org: org, saved_theme: saved_theme, video: video} do
      {conn, _view} = open_editor_with_draft(conn, user, org)

      admin = conn |> recycle() |> get("/admin")
      refute get_session(admin, :appearance_preview_id)
      refute get_session(admin, :member_preview_org_id)

      # The operator is no longer a member preview: public pages render as a
      # signed-out viewer with the saved theme only, and gated pages redirect.
      {:ok, browse, _html} = live(recycle(admin), "/browse")
      style = sv_root_style(browse)
      assert style =~ "--sv-bg-primary: #{saved_theme.background}"
      refute style =~ @draft_background
      refute has_element?(browse, "[data-test=appearance-preview-notice]")
      refute has_element?(browse, "[data-test=impersonation-banner]")

      events = admin |> recycle() |> get("/events") |> html_response(200)
      refute events =~ @draft_background
      refute events =~ "appearance-preview-notice"

      assert {:error, {:redirect, %{to: "/login"}}} = live(recycle(admin), "/watch/#{video.id}")

      {:ok, editor, _html} = live(recycle(admin), "/admin/appearance")
      refute has_element?(editor, "[data-test=appearance-preview-restored]")

      assert has_element?(
               editor,
               "[data-test=color-input-background] input[type=text][value='#{saved_theme.background}']"
             )

      refute has_element?(
               editor,
               "[data-test=color-input-background] input[type=text][value='#{@draft_background}']"
             )
    end

    test "saving persists the values and ends the draft", %{
      conn: conn,
      user: user,
      org: org,
      saved_theme: saved_theme
    } do
      # Guard: the value we save must differ from the seeded preset so the
      # assertions below cannot pass by accident.
      refute saved_theme.background == "#654321"

      {conn, view} = open_editor_with_draft(conn, user, org)
      preview_id = get_session(conn, :appearance_preview_id)
      assert Branding.get_theme_preview(org, preview_id)

      view
      |> form(@form, %{
        organization: %{accent_color_base: "#654321", display_font: @saved_font},
        theme: %{background: "#654321"}
      })
      |> render_submit()

      assert Branding.get_theme_or_default(org).background == "#654321"
      assert Branding.get_theme_preview(org, preview_id) == nil
      refute has_element?(view, "[data-test=appearance-preview-restored]")

      # Saved values only: the draft colour is gone and no draft notice is
      # shown. (The member preview itself is still active until `/admin`.)
      {:ok, home, _html} = live(recycle(conn), "/")
      style = sv_root_style(home)
      refute style =~ @draft_background
      refute style =~ "--color-accent: #{@draft_accent}"
      refute has_element?(home, "[data-test=appearance-preview-notice]")
      refute has_element?(home, "[data-test=appearance-preview-editor-link]")

      # A fresh editor mount shows the saved values, not a restored draft.
      {:ok, editor, _html} = live(recycle(conn), "/admin/appearance")
      refute has_element?(editor, "[data-test=appearance-preview-restored]")

      assert has_element?(
               editor,
               "[data-test=color-input-background] input[type=text][value='#654321']"
             )
    end
  end

  describe "review regressions" do
    setup :setup_org

    test "editor visit preserves a signed-in viewer until explicit preview", %{
      user: user,
      org: org
    } do
      viewer = insert(:viewer, organization: org, display_name: "Real Viewer")
      conn = conn_for_viewer(viewer)
      conn = put_session(conn, :user_token, Marquee.Accounts.generate_user_session_token(user))
      conn = get(conn, "/admin/appearance")

      {:ok, account, _} = live(recycle(conn), "/account")
      assert has_element?(account, "[data-test=account-display-name]", "Real Viewer")
      assert has_element?(account, "[data-test=account-edit-btn]")
      refute has_element?(account, "[data-test=impersonation-banner]")

      preview = conn |> recycle() |> get("/browse?preview=member")
      {:ok, account, _} = live(recycle(preview), "/account")
      assert has_element?(account, "[data-test=account-display-name]", "Member preview")
      refute has_element?(account, "[data-test=account-edit-btn]")
      render_click(account, "save", %{"viewer" => %{"display_name" => "Tampered"}})
      assert Marquee.Viewers.get_viewer_by_id(viewer.id).display_name == "Real Viewer"
    end

    test "restored notice clears on the first subsequent edit", %{
      conn: conn,
      user: user,
      org: org
    } do
      {conn, _} = open_editor_with_draft(conn, user, org)
      {:ok, editor, _} = live(recycle(conn), "/admin/appearance")
      assert has_element?(editor, "[data-test=appearance-preview-restored]")
      editor |> form(@form, %{theme: %{background: "#654321"}}) |> render_change()
      refute has_element?(editor, "[data-test=appearance-preview-restored]")
    end

    for restore? <- [false, true] do
      @restore_draft restore?
      test "full form preserves concurrent untouched values, restore=#{restore?}", %{
        conn: conn,
        user: user,
        org: org,
        saved_theme: saved_theme
      } do
        conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")
        {:ok, editor, _} = live(recycle(conn), "/admin/appearance")
        params = full_form_params(editor) |> put_in(["theme", "background"], @draft_background)
        render_change(editor, "validate_appearance", params)

        {:ok, _} = Branding.update_theme(saved_theme, %{surface: "#456789"})

        {:ok, _} =
          Marquee.Accounts.update_organization_branding(org, %{
            display_font: "Bodoni Moda",
            accent_color_base: "#224466"
          })

        {editor, params} =
          if @restore_draft do
            preview = conn |> recycle() |> get("/browse?preview=member")
            {:ok, browse, _} = live(recycle(preview), "/browse")
            assert sv_root_style(browse) =~ "--sv-bg-secondary: #456789"
            assert sv_root_style(browse) =~ "--sv-bg-primary: #{@draft_background}"
            html = preview |> recycle() |> get("/browse") |> html_response(200)
            assert html =~ "family=Bodoni+Moda"
            refute html =~ "family=DM+Serif+Display"

            {:ok, restored, _} = live(recycle(preview), "/admin/appearance")

            assert has_element?(
                     restored,
                     "[data-test=color-input-surface] input[value='#456789']"
                   )

            assert has_element?(
                     restored,
                     "[data-test=color-input-accent_color_base] input[value='#224466']"
                   )

            params = full_form_params(restored) |> put_in(["theme", "text_primary"], "#EEEEEE")
            render_change(restored, "validate_appearance", params)
            {restored, params}
          else
            {editor, params}
          end

        render_submit(editor, "save_appearance", params)
        saved = Branding.get_theme_or_default(org)
        assert saved.background == @draft_background
        assert saved.surface == "#456789"
        if @restore_draft, do: assert(saved.text_primary == "#EEEEEE")
        {:ok, updated_org} = Marquee.Accounts.get_organization(org.id)
        assert updated_org.display_font == "Bodoni Moda"
        assert updated_org.accent_color_base == "#224466"
      end
    end

    test "preview accent variants match persisted values", %{conn: conn, user: user, org: org} do
      conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")
      {:ok, editor, _} = live(recycle(conn), "/admin/appearance")

      params = %{
        organization: %{
          accent_color_base: "oklch(0.6 0.2 30)",
          accent_color_hover: "",
          accent_color_active: "",
          accent_color_subtle: ""
        }
      }

      editor |> form(@form, params) |> render_change()
      preview = conn |> recycle() |> get("/browse?preview=member")
      {:ok, browse, _} = live(recycle(preview), "/browse")
      style = sv_root_style(browse)
      assert style =~ "--color-accent-hover: oklch(0.660 0.200 30.000)"
      assert style =~ "--color-accent-active: oklch(0.540 0.200 30.000)"
      assert style =~ "--color-accent-subtle: oklch(0.28 0.100 30.000)"
      editor |> form(@form, params) |> render_submit()
      {:ok, saved} = Marquee.Accounts.get_organization(org.id)
      assert style =~ "--color-accent-hover: #{saved.accent_color_hover}"
      assert style =~ "--color-accent-active: #{saved.accent_color_active}"
      assert style =~ "--color-accent-subtle: #{saved.accent_color_subtle}"
    end

    test "explicit accent variants survive form preview and save", %{
      conn: conn,
      user: user,
      org: org
    } do
      conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")
      {:ok, editor, _} = live(recycle(conn), "/admin/appearance")

      params = %{
        organization: %{
          accent_color_base: "#112233",
          accent_color_hover: "#223344",
          accent_color_active: "#334455",
          accent_color_subtle: "#445566"
        }
      }

      editor |> form(@form, params) |> render_change()

      [inline] =
        editor
        |> element("[data-test=preview-frame]")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-test=preview-frame] > .sv-root")
        |> LazyHTML.attribute("style")

      preview = conn |> recycle() |> get("/browse?preview=member")
      {:ok, browse, _} = live(recycle(preview), "/browse")

      for style <- [inline, sv_root_style(browse)] do
        assert style =~ "--color-accent-hover: #223344"
        assert style =~ "--color-accent-active: #334455"
        assert style =~ "--color-accent-subtle: #445566"
      end

      editor |> form(@form, params) |> render_submit()
      {:ok, saved} = Marquee.Accounts.get_organization(org.id)
      assert saved.accent_color_hover == "#223344"
      assert saved.accent_color_active == "#334455"
      assert saved.accent_color_subtle == "#445566"
    end

    for edit <- [:base, :clear_hover] do
      @accent_edit edit
      test "full form accent edit #{@accent_edit} preserves explicit variants and derives cleared slots",
           %{
             conn: conn,
             user: user,
             org: org
           } do
        {:ok, org} =
          Marquee.Accounts.update_organization_branding(org, %{
            accent_color_base: "oklch(0.6 0.2 30)",
            accent_color_hover: "#223344",
            accent_color_active: "#334455",
            accent_color_subtle: "#445566"
          })

        conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")
        {:ok, editor, _} = live(recycle(conn), "/admin/appearance")
        params = full_form_params(editor)
        assert params["organization"]["accent_color_hover"] == "#223344"
        assert params["organization"]["accent_color_active"] == "#334455"
        assert params["organization"]["accent_color_subtle"] == "#445566"

        {params, base, hover} =
          if @accent_edit == :base do
            {put_in(params, ["organization", "accent_color_base"], "oklch(0.7 0.2 30)"),
             "oklch(0.7 0.2 30)", "#223344"}
          else
            {put_in(params, ["organization", "accent_color_hover"], ""), "oklch(0.6 0.2 30)",
             "oklch(0.660 0.200 30.000)"}
          end

        render_change(editor, "validate_appearance", params)

        [inline] =
          editor
          |> element("[data-test=preview-frame]")
          |> render()
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("[data-test=preview-frame] > .sv-root")
          |> LazyHTML.attribute("style")

        preview = conn |> recycle() |> get("/browse?preview=member")
        {:ok, browse, _} = live(recycle(preview), "/browse")
        viewer_style = sv_root_style(browse)
        render_submit(editor, "save_appearance", params)
        {:ok, saved} = Marquee.Accounts.get_organization(org.id)

        assert saved.accent_color_base == base
        assert saved.accent_color_hover == hover
        assert saved.accent_color_active == "#334455"
        assert saved.accent_color_subtle == "#445566"

        for style <- [inline, viewer_style] do
          assert style =~ "--color-accent: #{base}"
          assert style =~ "--color-accent-hover: #{hover}"
          assert style =~ "--color-accent-active: #334455"
          assert style =~ "--color-accent-subtle: #445566"
        end
      end
    end

    test "invalid font and CSS colors never reach preview rendering", %{
      conn: conn,
      user: user,
      org: org
    } do
      conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")
      {:ok, editor, _} = live(recycle(conn), "/admin/appearance")
      malicious_font = "Foo&family=Injected'; --injected: yes; /*"
      malicious_color = "red; --injected: yes"

      render_change(editor, "validate_appearance", %{
        "organization" => %{
          "display_font" => malicious_font,
          "accent_color_base" => malicious_color
        },
        "theme" => %{"background" => @draft_background, "surface" => malicious_color}
      })

      [frame_style] =
        editor
        |> element("[data-test=preview-frame]")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-test=preview-frame] > .sv-root")
        |> LazyHTML.attribute("style")

      refute frame_style =~ "Injected"
      refute frame_style =~ "--injected"
      preview = conn |> recycle() |> get("/browse?preview=member")
      html = html_response(preview, 200)
      refute html =~ "Injected"
      refute html =~ "--injected"
      assert html =~ "--sv-bg-primary: #{@draft_background}"
    end
  end

  # Use every successful named form control, matching the browser payload.
  defp full_form_params(view) do
    document = view |> element(@form) |> render() |> LazyHTML.from_fragment()

    inputs =
      document
      |> LazyHTML.query("input[name]")
      |> Enum.map(fn input ->
        {[name], values} = {LazyHTML.attribute(input, "name"), LazyHTML.attribute(input, "value")}
        {name, List.first(values) || ""}
      end)

    selects =
      document
      |> LazyHTML.query("select[name]")
      |> Enum.map(fn select ->
        [name] = LazyHTML.attribute(select, "name")
        values = select |> LazyHTML.query("option[selected]") |> LazyHTML.attribute("value")
        {name, List.first(values) || ""}
      end)

    (inputs ++ selects) |> URI.encode_query() |> Query.decode()
  end
end
