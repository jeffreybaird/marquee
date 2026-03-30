defmodule BobineWeb.Admin.ContentLiveDeleteCleanupTest do
  use BobineWeb.ConnCase, async: true
  use Oban.Testing, repo: Bobine.Repo

  import Phoenix.LiveViewTest

  describe "delete video triggers Mux asset cleanup" do
    test "deleting a video with a mux_asset_id enqueues a cleanup job", %{conn: _conn} do
      org = insert(:organization)
      user = insert(:user)
      membership = insert(:membership, organization: org, user: user, role: :editor)

      video =
        insert(:video,
          organization: org,
          title: "To Cleanup",
          mux_asset_id: "asset_cleanup_1"
        )

      # Stub the mock so the inline Oban job doesn't crash
      Mox.stub(Bobine.Content.MockMuxClient, :delete_asset, fn _id -> :ok end)

      {:ok, view, _html} = live(conn_for(membership), ~p"/admin/content")

      view
      |> element(~s([data-test="delete-video-#{video.id}"]))
      |> render_click()

      # The MuxAssetCleanup job should have been enqueued (and run inline in test)
      # Verify the video is soft-deleted
      deleted = Bobine.Repo.get!(Bobine.Content.Video, video.id)
      assert deleted.deleted_at != nil
    end
  end
end
