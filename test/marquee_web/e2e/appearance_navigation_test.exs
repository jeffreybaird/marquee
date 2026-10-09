defmodule MarqueeWeb.E2E.AppearanceNavigationTest do
  use MarqueeWeb.WallabyCase

  @moduletag :e2e

  test "sidebar exit abandons an active appearance draft", %{session: session} do
    org = insert(:organization)
    user = insert(:user)
    insert(:membership, organization: org, user: user, role: :admin)

    session =
      session
      |> resize_window(1440, 1000)
      |> log_in_session(user, org)
      |> visit("/admin/appearance")
      |> fill_in(css("[data-test=color-input-background] input[type=text]"), with: "#123456")
      |> assert_has(css("[data-test=preview-frame] [style*='--sv-bg-primary: #123456']"))
      |> click(css("[data-test=admin-nav-dashboard]"))
      |> assert_has(css("h1", text: "Dashboard"))
      |> visit("/browse")
      |> assert_has(css("[data-test=sv-root]"))

    assert current_path(session) == "/browse"
    assert_no_preview_markers(session)

    session =
      session |> visit("/admin/appearance") |> assert_has(css("[data-test=preview-frame]"))

    assert current_path(session) == "/admin/appearance"
    assert_no_preview_markers(session)

    refute session
           |> find(css("[data-test=color-input-background] input[type=text]"))
           |> Wallaby.Element.value() == "#123456"
  end

  for entry <- [:sidebar, :branding] do
    @entry entry
    test "draft survives actual preview card navigation after #{@entry} entry", %{
      session: session
    } do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :admin)

      video =
        insert(:video,
          organization: org,
          title: "Preview Navigation",
          mux_status: "ready",
          published: true
        )

      row = insert(:row, organization: org, source_type: :curated, visible: true)
      insert(:row_item, organization: org, row: row, video: video, position: 0)
      session = session |> resize_window(1440, 1000) |> log_in_session(user, org)

      session =
        if @entry == :sidebar do
          click(session, css("[data-test=admin-nav-appearance]"))
        else
          visit(session, "/admin/branding")
        end

      session =
        session
        |> assert_has(css("[data-test=preview-frame]"))
        |> fill_in(css("[data-test=color-input-background] input[type=text]"), with: "#123456")
        |> assert_has(css("[data-test=preview-frame] [style*='--sv-bg-primary: #123456']"))
        |> click(css("[data-test=preview-frame] a[href*='/watch/#{video.id}']", at: 0))
        |> assert_has(css("[data-test=sv-root][style*='--sv-bg-primary: #123456']"))
        |> assert_has(css("[data-test=impersonation-banner]", text: "Member preview"))

      assert current_path(session) =~ "/watch/#{video.id}"

      session =
        session
        |> click(css("[data-test=appearance-preview-editor-link]"))
        |> assert_has(css("[data-test=appearance-preview-restored]"))

      assert session
             |> find(css("[data-test=color-input-background] input[type=text]"))
             |> Wallaby.Element.value() == "#123456"

      session =
        session
        |> click(css("[data-test=admin-nav-dashboard]"))
        |> assert_has(css("h1", text: "Dashboard"))
        |> visit("/browse")
        |> assert_has(css("[data-test=sv-root]"))

      assert current_path(session) == "/browse"
      assert_no_preview_markers(session)
      root_style = session |> find(css("[data-test=sv-root]")) |> Wallaby.Element.attr("style")
      refute root_style =~ "--sv-bg-primary: #123456"
    end
  end

  # Call only after a positive page marker confirms navigation has completed.
  # Read absence once instead of paying Wallaby's full retry window per selector.
  defp assert_no_preview_markers(session) do
    execute_script(
      session,
      """
      return document.querySelectorAll(
        '[data-test=appearance-preview-notice], [data-test=impersonation-banner], [data-test=appearance-preview-restored]'
      ).length;
      """,
      fn count -> assert count == 0 end
    )
  end
end
