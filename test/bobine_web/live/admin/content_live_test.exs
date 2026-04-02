defmodule BobineWeb.Admin.ContentLiveTest do
  use BobineWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  describe "responsive layout" do
    test "mobile sidebar toggle elements are present", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")

      # Mobile header with hamburger button exists
      assert html =~ ~s(data-test="org-name-mobile")
      assert html =~ "hero-bars-3"

      # Sidebar with nav links exists
      assert html =~ ~s(id="admin-sidebar")
      assert html =~ ~s(id="admin-overlay")
      assert html =~ ~s(data-test="admin-nav-content")
    end

    test "sidebar open uses JS.remove_class not checkbox peer", %{conn: _conn} do
      # Regression: the CSS-only peer-checked approach broke under LiveView
      # DOM patching. The fix uses phx-click with JS commands instead.
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")

      # Must NOT have a checkbox-based drawer (the broken approach)
      refute html =~ ~s(id="admin-drawer")
      # Must use phx-click JS commands on the hamburger button
      assert html =~ "phx-click"
    end
  end

  describe "access control" do
    test "admin can access content page", %{conn: _conn} do
      membership = insert(:membership, role: :admin)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Content"
    end

    test "editor can access content page", %{conn: _conn} do
      membership = insert(:membership, role: :editor)
      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Content"
    end

    test "unauthenticated user is redirected", %{conn: conn} do
      org = insert(:organization)
      conn = Map.put(conn, :host, "#{org.slug}.localhost")
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/content")
      assert path == ~p"/users/log-in"
    end
  end

  describe "video list" do
    test "renders video list for the organization", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      video = insert(:video, organization: org, title: "Test Video", mux_status: "ready")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Test Video"
      assert html =~ ~s(data-test="video-row-#{video.id}")
    end

    test "shows empty state when no videos exist", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ ~s(data-test="empty-state")
      assert html =~ "No videos yet"
    end

    test "videos from other organizations are not visible", %{conn: _conn} do
      org = insert(:organization)
      other_org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      insert(:video, organization: other_org, title: "Other Org Video")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      refute html =~ "Other Org Video"
    end

    test "upload button is visible for editors", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ ~s(data-test="upload-btn")
    end

    test "delete button soft-deletes the video", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "To Delete")

      # The MuxAssetCleanup job runs inline and calls delete_asset
      Mox.stub(Bobine.Content.MockMuxClient, :delete_asset, fn _asset_id -> :ok end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      html =
        view
        |> element(~s([data-test="delete-video-#{video.id}"]))
        |> render_click()

      refute html =~ "To Delete"
    end

    test "upload_error event is handled without crashing the LiveView", %{conn: _conn} do
      # This tests the fix for the bug where the modal closed before the
      # MuxUploader hook could read the file, causing "No file selected" error.
      # The LiveView must handle this gracefully — not crash.
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      # Simulate the MuxUploader hook reporting an error via pushEvent
      # The LiveView should handle this without crashing
      assert render_hook(view, "upload_error", %{
               "video_id" => Ecto.UUID.generate(),
               "error" => "No file selected"
             })

      # The LiveView should still be alive and rendering
      assert render(view) =~ "Content"
    end

    test "submit_upload shows clearer mux failure feedback", %{conn: _conn} do
      verify_on_exit!()

      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      expect(Bobine.Content.MockMuxClient, :create_direct_upload, fn _params ->
        {:error, :mux_error,
         %{type: "invalid_parameters", messages: ["asset limit reached on free tier"]}}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      render_click(view, "open_upload")

      # Simulate file selection from the hook
      render_hook(view, "files_selected", %{
        "files" => [%{"client_id" => "file_1", "name" => "quota_test.mp4"}]
      })

      render_submit(view, "submit_upload", %{
        "titles" => %{"file_1" => "Quota Test"}
      })

      html = render(view)

      assert html =~ "Mux could not start this upload."
      assert html =~ "asset or upload limit"
      assert html =~ "asset limit reached on free tier"
    end

    test "upload_complete event closes modal", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      # Open modal first
      render_click(view, "open_upload")
      assert render(view) =~ ~s(data-test="upload-modal")

      # Simulate upload completion
      render_hook(view, "upload_complete", %{
        "video_id" => Ecto.UUID.generate()
      })

      # Modal should be closed after upload completes
      refute render(view) =~ ~s(data-test="upload-modal")
    end

    test "search filters video list by title", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      insert(:video, organization: org, title: "Alpha Video")
      insert(:video, organization: org, title: "Beta Film")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      html = render_change(view, "search", %{"search" => "Alpha"})
      assert html =~ "Alpha Video"
      refute html =~ "Beta Film"
    end

    test "video title opens detail view", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "Watchable", mux_status: "ready")

      {:ok, view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ ~s(data-test="view-video-#{video.id}")

      html = render_click(view, "view_video", %{id: video.id})
      assert html =~ "data-test=\"video-detail\""
      assert html =~ "Watchable"
    end
  end

  describe "video detail view" do
    test "shows video detail with back button", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "Detail Video", mux_status: "ready")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      html = render_click(view, "view_video", %{id: video.id})
      assert html =~ "data-test=\"video-detail\""
      assert html =~ "data-test=\"back-to-list-btn\""
      assert html =~ "Detail Video"
    end

    test "back button returns to video list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "Back Test")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      render_click(view, "view_video", %{id: video.id})

      html = render_click(view, "back_to_list")
      assert html =~ "data-test=\"video-search\""
      refute html =~ "data-test=\"video-detail\""
    end

    test "edit video title and description", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "Original Title")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      render_click(view, "view_video", %{id: video.id})
      render_click(view, "edit_video")

      html = render(view)
      assert html =~ "data-test=\"video-edit-form\""

      html =
        view
        |> form("[data-test=\"video-edit-form\"] form", %{
          video: %{title: "Updated Title", description: "New desc"}
        })
        |> render_submit()

      assert html =~ "Updated Title"
    end

    test "cancel edit returns to read-only view", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)
      video = insert(:video, organization: org, title: "Cancel Test")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      render_click(view, "view_video", %{id: video.id})
      render_click(view, "edit_video")
      render_click(view, "cancel_edit")

      html = render(view)
      refute html =~ "data-test=\"video-edit-form\""
      assert html =~ "data-test=\"video-title\""
    end

    test "viewer_support cannot see edit button on detail", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)
      video = insert(:video, organization: org, title: "Read Only")

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      html = render_click(view, "view_video", %{id: video.id})
      refute html =~ "data-test=\"edit-video-btn\""
    end
  end

  describe "video tag management" do
    setup do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      scope =
        Bobine.Repo.preload(membership, [:user, :organization])
        |> then(fn m ->
          Bobine.Accounts.Scope.for_user(m.user)
          |> Bobine.Accounts.Scope.with_organization(m.organization, m)
        end)

      video = insert(:video, organization: org, title: "Taggable")
      {:ok, tag} = Bobine.Content.create_tag(scope, %{name: "yoga"})
      {:ok, tag2} = Bobine.Content.create_tag(scope, %{name: "beginner"})

      %{org: org, membership: membership, scope: scope, video: video, tag: tag, tag2: tag2}
    end

    test "shows no tags message when video has no tags", ctx do
      {:ok, view, _html} = live(conn_for(ctx.membership), ~p"/admin/content")
      html = render_click(view, "view_video", %{id: ctx.video.id})
      assert html =~ "data-test=\"no-tags\""
      assert html =~ "No tags assigned"
    end

    test "shows existing tags as pills", ctx do
      {:ok, _} = Bobine.Content.tag_video(ctx.scope, ctx.video, ctx.tag)

      {:ok, view, _html} = live(conn_for(ctx.membership), ~p"/admin/content")
      html = render_click(view, "view_video", %{id: ctx.video.id})

      assert html =~ "data-test=\"video-tag-#{ctx.tag.id}\""
      assert html =~ "yoga"
    end

    test "add tag via picker", ctx do
      {:ok, view, _html} = live(conn_for(ctx.membership), ~p"/admin/content")
      render_click(view, "view_video", %{id: ctx.video.id})

      render_click(view, "open_tag_picker")
      html = render(view)
      assert html =~ "data-test=\"tag-picker\""
      assert html =~ "data-test=\"pick-tag-#{ctx.tag.id}\""

      html = render_click(view, "add_tag", %{"tag-id" => ctx.tag.id})
      assert html =~ "data-test=\"video-tag-#{ctx.tag.id}\""
      assert html =~ "yoga"
    end

    test "remove tag via pill button", ctx do
      {:ok, _} = Bobine.Content.tag_video(ctx.scope, ctx.video, ctx.tag)

      {:ok, view, _html} = live(conn_for(ctx.membership), ~p"/admin/content")
      render_click(view, "view_video", %{id: ctx.video.id})

      html = render(view)
      assert html =~ "data-test=\"video-tag-#{ctx.tag.id}\""

      html =
        view
        |> element(~s([data-test="remove-tag-#{ctx.tag.id}"]))
        |> render_click()

      refute html =~ "data-test=\"video-tag-#{ctx.tag.id}\""
    end

    test "tag picker excludes already-assigned tags", ctx do
      {:ok, _} = Bobine.Content.tag_video(ctx.scope, ctx.video, ctx.tag)

      {:ok, view, _html} = live(conn_for(ctx.membership), ~p"/admin/content")
      render_click(view, "view_video", %{id: ctx.video.id})
      render_click(view, "open_tag_picker")

      html = render(view)
      refute html =~ "data-test=\"pick-tag-#{ctx.tag.id}\""
      assert html =~ "data-test=\"pick-tag-#{ctx.tag2.id}\""
    end

    test "viewer_support cannot see add tag button", ctx do
      vs_membership =
        insert(:membership, organization: ctx.org, user: insert(:user), role: :viewer_support)

      {:ok, view, _html} = live(conn_for(vs_membership), ~p"/admin/content")
      html = render_click(view, "view_video", %{id: ctx.video.id})
      refute html =~ "data-test=\"add-tag-btn\""
    end
  end

  describe "multi-file upload" do
    test "files_selected event shows title inputs for each file", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      render_click(view, "open_upload")

      html =
        render_hook(view, "files_selected", %{
          "files" => [
            %{"client_id" => "file_1", "name" => "my_video.mp4"},
            %{"client_id" => "file_2", "name" => "another-clip.mov"}
          ]
        })

      # Title inputs should appear with auto-generated titles from filenames
      assert html =~ ~s(data-test="upload-title-file_1")
      assert html =~ ~s(data-test="upload-title-file_2")
      assert html =~ "my video"
      assert html =~ "another clip"
      assert html =~ "Upload 2 Videos"
    end

    test "files_selected strips file extension and cleans up filename for title", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      render_click(view, "open_upload")

      html =
        render_hook(view, "files_selected", %{
          "files" => [%{"client_id" => "file_1", "name" => "my_awesome_video.mp4"}]
        })

      assert html =~ "my awesome video"
      assert html =~ "Upload 1 Video"
    end

    test "submit_upload with multiple files creates upload URLs for each", %{conn: _conn} do
      import Mox

      verify_on_exit!()

      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      # Expect two Mux upload URL creations
      expect(Bobine.Content.MockMuxClient, :create_direct_upload, 2, fn _params ->
        upload_id = "upload_#{System.unique_integer([:positive])}"
        {:ok, %{"id" => upload_id, "url" => "https://storage.mux.com/#{upload_id}"}}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      render_click(view, "open_upload")

      render_hook(view, "files_selected", %{
        "files" => [
          %{"client_id" => "file_1", "name" => "first.mp4"},
          %{"client_id" => "file_2", "name" => "second.mp4"}
        ]
      })

      html =
        render_submit(view, "submit_upload", %{
          "titles" => %{"file_1" => "First Video", "file_2" => "Second Video"}
        })

      # Should be in uploading state
      assert html =~ "Uploading"
    end

    test "upload_complete for last file in batch closes modal", %{conn: _conn} do
      import Mox

      verify_on_exit!()

      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      expect(Bobine.Content.MockMuxClient, :create_direct_upload, 2, fn _params ->
        upload_id = "upload_#{System.unique_integer([:positive])}"
        {:ok, %{"id" => upload_id, "url" => "https://storage.mux.com/#{upload_id}"}}
      end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      render_click(view, "open_upload")

      render_hook(view, "files_selected", %{
        "files" => [
          %{"client_id" => "file_1", "name" => "a.mp4"},
          %{"client_id" => "file_2", "name" => "b.mp4"}
        ]
      })

      render_submit(view, "submit_upload", %{
        "titles" => %{"file_1" => "Video A", "file_2" => "Video B"}
      })

      # Complete first upload — modal stays open
      render_hook(view, "upload_complete", %{"video_id" => Ecto.UUID.generate()})
      html = render(view)
      assert html =~ "Uploading"

      # Complete second upload — modal closes
      render_hook(view, "upload_complete", %{"video_id" => Ecto.UUID.generate()})
      html = render(view)
      refute html =~ ~s(data-test="upload-modal")
      assert html =~ "All 2 uploads complete"
    end

    test "close_upload resets file selection", %{conn: _conn} do
      membership = insert(:membership, role: :editor)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")
      render_click(view, "open_upload")

      render_hook(view, "files_selected", %{
        "files" => [%{"client_id" => "file_1", "name" => "video.mp4"}]
      })

      assert render(view) =~ ~s(data-test="upload-form")

      # Close and reopen — should be back to file picker
      render_click(view, "close_upload")
      html = render_click(view, "open_upload")
      assert html =~ ~s(data-test="upload-file-picker")
      refute html =~ ~s(data-test="upload-form")
    end
  end

  describe "RBAC on content management" do
    test "viewer_support can view content list", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)

      insert(:video, organization: org, title: "Visible Video")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      assert html =~ "Visible Video"
    end

    test "viewer_support cannot see upload button", %{conn: _conn} do
      # viewer_support should have read-only access — no upload capability
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      refute html =~ ~s(data-test="upload-btn")
    end

    test "viewer_support cannot see delete button", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :viewer_support)
      video = insert(:video, organization: org, title: "Protected Video")

      {:ok, _view, html} = live(conn_for(membership), ~p"/admin/content")
      refute html =~ ~s(data-test="delete-video-#{video.id}")
    end
  end
end
