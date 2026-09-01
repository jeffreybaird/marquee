defmodule MarqueeWeb.E2E.ContentUploadTest do
  use MarqueeWeb.WallabyCase

  @moduletag :e2e

  describe "content management page" do
    test "upload button opens modal in real browser", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :editor)

      session
      |> log_in_session(user, org)
      |> Wallaby.Browser.visit("/admin/content?org=#{org.slug}")
      |> assert_has(Query.css("[data-test='upload-btn']"))
      |> Wallaby.Browser.click(Query.css("[data-test='upload-btn']"))
      |> assert_has(Query.css("[data-test='upload-modal']"))
    end

    test "content page shows videos for the org", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "E2E Test Video", mux_status: "ready")

      session
      |> log_in_session(user, org)
      |> Wallaby.Browser.visit("/admin/content?org=#{org.slug}")
      |> assert_has(Query.css("[data-test='video-row-#{video.id}']"))
      |> assert_has(Query.text("E2E Test Video"))
    end

    test "empty state shown when no videos", %{session: session} do
      org = insert(:organization)
      user = insert(:user)
      insert(:membership, organization: org, user: user, role: :editor)

      session
      |> log_in_session(user, org)
      |> Wallaby.Browser.visit("/admin/content?org=#{org.slug}")
      |> assert_has(Query.css("[data-test='empty-state']"))
    end
  end
end
