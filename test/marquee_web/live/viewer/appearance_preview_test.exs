defmodule MarqueeWeb.Viewer.AppearancePreviewTest do
  @moduledoc """
  Issue #21 — unsaved appearance changes must survive navigating from the
  `/admin/appearance` preview into the real viewer site and back.

  Opening the editor starts an appearance preview session. While it is active
  the operator browses the viewer site as a read-only member preview that
  renders the *draft* theme, with a banner back to the editor. Returning to
  the editor restores the draft. Any other admin page, or saving, ends it.
  """

  use MarqueeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Marquee.Branding
  alias Marquee.Branding.Theme

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

    {conn, view}
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

    test "starts an appearance preview session and a member preview", %{
      conn: conn,
      user: user,
      org: org
    } do
      conn = conn |> log_in_user(user) |> get("/admin/appearance?org=#{org.slug}")

      assert is_binary(get_session(conn, :appearance_preview_id))
      assert get_session(conn, :member_preview_org_id) == org.id
      assert is_binary(get_session(conn, :member_preview_viewer_id))
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
      {conn, _view} = open_editor_with_draft(conn, user, org)

      other = conn |> recycle() |> get("/browse?org=#{other_org.slug}")

      refute get_session(other, :appearance_preview_id)
      refute get_session(other, :member_preview_org_id)
      refute other.assigns[:theme_preview]

      # `/browse` is public, so the other org's site renders and must not
      # carry the draft.
      html = html_response(other, 200)
      refute html =~ @draft_background
      refute html =~ "appearance-preview-notice"
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
end
