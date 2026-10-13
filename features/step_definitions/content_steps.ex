defmodule MarqueeFeatures.Steps.Content do
  @moduledoc """
  Video-related step definitions for content_management.feature.

  Edit + soft-delete now drive the admin UI via Wallaby. Restore still
  calls `Content.restore_video/2` directly because no operator-facing
  restore surface exists yet — flagged inline so the step can be
  promoted once that UI lands.
  """

  use Cucumberex.DSL

  use Wallaby.DSL
  import Wallaby.Query
  import Phoenix.ConnTest, only: [build_conn: 0, post: 3]
  import Plug.Conn, only: [put_req_header: 3]
  import Marquee.Factory
  import ExUnit.Assertions
  import MarqueeFeatures.Support.Browser

  alias Marquee.Content
  alias Marquee.Content.MockMuxClient
  alias Marquee.Repo
  alias Marquee.Storage.MockSpacesClient
  alias Marquee.Viewers.ViewerToken
  alias MarqueeFeatures.UploadStubServer
  alias Wallaby.Element

  @endpoint MarqueeWeb.Endpoint

  # ---- Setup --------------------------------------------------------------

  given_("a video exists in the content library", fn world ->
    # Published + ready so the thumbnail scenarios can also check how the
    # video renders on the viewer site.
    video = ready_video(world.org, title: "Library Feature")
    Map.put(world, :video, video)
  end)

  given_("a video has been soft-deleted", fn world ->
    video = insert(:video, organization: world.org, mux_status: "ready")
    {:ok, deleted} = Content.delete_video(world.scope, video)
    Map.merge(world, %{video: video, deleted_video: deleted})
  end)

  # ---- Edit metadata (Wallaby) -------------------------------------------

  when_("I edit the title or description and save", fn world ->
    session =
      world.session
      |> visit("/admin/content?org=#{world.org.slug}")
      |> click(css("[data-test=view-video-#{world.video.id}]"))
      |> click(css("[data-test=edit-video-btn]"))
      |> fill_in(css("[data-test=video-title-input]"), with: "Updated Title")
      |> fill_in(css("[data-test=video-description-input]"), with: "Updated description text")
      |> click(css("[data-test=save-video-btn]"))

    Map.put(world, :session, session)
  end)

  then_("the video record is updated with the new metadata", fn world ->
    assert_text(world.session, "Updated Title")
    assert_text(world.session, "Updated description text")

    # Secondary persistence check — the UI confirmation above is the
    # user-observable outcome; this guards against a stale page
    # rendering cached assigns.
    fetched = Content.get_video!(world.org, world.video.id)
    assert fetched.title == "Updated Title"
    assert fetched.description == "Updated description text"

    world
  end)

  # ---- Soft-delete (Wallaby) ---------------------------------------------

  when_("I delete the video", fn world ->
    session = visit(world.session, "/admin/content?org=#{world.org.slug}")
    Mox.set_mox_global()

    Mox.expect(MockMuxClient, :delete_asset, fn asset_id ->
      assert asset_id == world.video.mux_asset_id
      :ok
    end)

    try do
      accept_confirm(session, fn s ->
        click(s, css("[data-test=delete-video-#{world.video.id}]"))
      end)

      await_gone(session, css("[data-test=view-video-#{world.video.id}]"))
      Mox.verify!()
      Map.put(world, :session, session)
    after
      Mox.set_mox_private()
    end
  end)

  then_("the video is marked with a deleted_at timestamp", fn world ->
    # The DB check is primary here because deleted_at is an invisible
    # side effect — the user-observable result (the row disappearing
    # from the list) is covered by the following step.
    fetched = Content.get_video!(world.org, world.video.id)
    assert fetched.deleted_at != nil
    Map.put(world, :deleted_video, fetched)
  end)

  then_("it no longer appears in content listings", fn world ->
    session = visit(world.session, "/admin/content?org=#{world.org.slug}")
    refute_has(session, css("[data-test=view-video-#{world.video.id}]"))
    Map.put(world, :session, session)
  end)

  # ---- Restore (legacy — context-direct) ---------------------------------
  # TODO: rewrite with Wallaby once an operator-facing restore surface
  # exists. There's no admin UI for it today, so asserting on a button
  # or link would silently pass against a non-existent element.

  then_("it can be restored", fn world ->
    {:ok, restored} = Content.restore_video(world.scope, world.deleted_video)
    assert is_nil(restored.deleted_at)
    world
  end)

  when_("I restore the video", fn world ->
    {:ok, restored} = Content.restore_video(world.scope, world.deleted_video)
    Map.put(world, :restored_video, restored)
  end)

  then_("it reappears in the content library", fn world ->
    %{results: videos} = Content.list_videos(world.org)
    ids = Enum.map(videos, & &1.id)
    assert world.restored_video.id in ids
    world
  end)

  # ---- Upload (Wallaby + local stand-in for the Mux upload URL) -------------

  when_("I select one or more video files and submit the upload form", fn world ->
    test_pid = self()
    stub = UploadStubServer.start(test_pid, hold: true)
    counter = :counters.new(1, [])

    files =
      for {name, bytes} <- [
            {"cuke_upload_one.mp4", "first fake video payload"},
            {"cuke_upload_two.mp4", "second fake video payload, a little longer"}
          ] do
        path = Path.join(scratch_dir(), name)
        File.write!(path, bytes)
        %{name: name, path: path, bytes: bytes}
      end

    # Real Mux is never contacted: the direct-upload URL handed to the
    # browser points at the local stub server, which records each PUT.
    Mox.set_mox_global()

    Mox.stub(MockMuxClient, :create_direct_upload, fn params ->
      :counters.add(counter, 1, 1)
      n = :counters.get(counter, 1)
      send(test_pid, {:mux_direct_upload_requested, n, params})
      {:ok, %{"id" => "upload_cuke_#{n}", "url" => "#{stub.base_url}/mux/upload_cuke_#{n}"}}
    end)

    try do
      session =
        world.session
        |> visit_content(world)
        |> click(css("[data-test=upload-btn]"))
        |> attach_file(css("[data-test=upload-file]"), path: Enum.map_join(files, "\n", & &1.path))
        |> assert_has(css("[data-test=upload-form]"))
        |> click(css("[data-test=upload-submit]"))

      Map.merge(world, %{session: session, upload_stub: stub, upload_files: files})
    rescue
      error ->
        Mox.set_mox_private()
        UploadStubServer.stop(stub)
        reraise error, __STACKTRACE__
    end
  end)

  then_("the files are uploaded directly to Mux", fn world ->
    [first, second] = world.upload_files

    try do
      assert_receive {:mux_direct_upload_requested, 1, _params}, 10_000
      assert_receive {:mux_direct_upload_requested, 2, _params}, 10_000
    after
      Mox.set_mox_private()
    end

    # Files go one at a time, each straight from the browser to its own
    # direct-upload URL. The stub holds each response open until released.
    assert_receive {:upload_stub_received, handler_one, "/mux/upload_cuke_1", body_one}, 15_000
    assert body_one == first.bytes

    # While the first upload is in flight the operator sees it in progress.
    assert_has(world.session, css("[data-test=upload-progress-section]", text: "Uploading 1 of 2"))
    assert_has(world.session, css("[data-test=upload-progress]"))
    UploadStubServer.release(handler_one)

    assert_receive {:upload_stub_received, handler_two, "/mux/upload_cuke_2", body_two}, 15_000
    assert body_two == second.bytes

    Map.merge(world, %{held_upload: handler_two, progress_seen: [1]})
  end)

  then_("I see real-time upload progress for each file", fn world ->
    # Always stop the stub listener, even when an assertion fails.
    try do
      assert world.progress_seen == [1], "expected progress to have been shown for the first file"

      world.session
      |> assert_has(css("[data-test=upload-progress-section]", text: "Uploading 2 of 2"))
      |> assert_has(css("[data-test=upload-progress]"))

      UploadStubServer.release(world.held_upload)

      # Once the last file lands the progress UI goes away (retrying wait).
      await_gone(world.session, css("[data-test=upload-progress-section]"))
    after
      UploadStubServer.stop(world.upload_stub)
    end

    Map.update!(world, :progress_seen, &(&1 ++ [2]))
  end)

  then_("video records are created with status {string}", fn world, status ->
    videos =
      for n <- 1..length(world.upload_files) do
        video = Repo.get_by!(Marquee.Content.Video, organization_id: world.org.id, mux_upload_id: "upload_cuke_#{n}")
        assert video.mux_status == mux_status_for(status),
               "expected #{video.title} to be #{status} (mux_status #{mux_status_for(status)}), got #{video.mux_status}"

        video
      end

    assert Enum.sort(Enum.map(videos, & &1.title)) == ["cuke upload one", "cuke upload two"]

    Enum.each(videos, fn video ->
      assert_has(
        world.session,
        css("[data-test=video-status-#{video.id}]", text: status_label_for(status))
      )
    end)

    world
  end)

  # ---- Mux webhooks -----------------------------------------------------------

  given_("a video was uploaded and is processing in Mux", fn world ->
    n = System.unique_integer([:positive])

    video =
      insert(:video,
        organization: world.org,
        title: "Processing Upload #{n}",
        mux_status: "preparing",
        mux_asset_id: "asset_cuke_#{n}",
        mux_playback_id: nil,
        duration: nil
      )

    session =
      world.session
      |> visit_content(world)
      |> assert_has(css("[data-test=video-status-#{video.id}]", text: "Processing"))
      # Marks this document; a reload would drop the marker.
      |> execute_script("document.documentElement.setAttribute('data-cm-no-reload', ''); return true;")

    Map.merge(world, %{session: session, video: video})
  end)

  when_("Mux signals the asset is ready via webhook", fn world ->
    payload = %{
      type: "video.asset.ready",
      data: %{
        id: world.video.mux_asset_id,
        status: "ready",
        duration: 125.5,
        max_stored_resolution: "HD",
        playback_ids: [%{id: "playback_cuke_#{world.video.id}", policy: "public"}]
      }
    }

    conn = post_mux_webhook(payload)
    assert conn.status == 200, "expected Mux webhook to be accepted, got #{conn.status}"
    world
  end)

  when_("Mux signals an asset error via webhook", fn world ->
    payload = %{
      type: "video.asset.errored",
      data: %{
        id: world.video.mux_asset_id,
        status: "errored",
        errors: %{type: "invalid_input", messages: ["The input file could not be decoded"]}
      }
    }

    conn = post_mux_webhook(payload)
    assert conn.status == 200, "expected Mux webhook to be accepted, got #{conn.status}"
    world
  end)

  then_("the video status updates to {string}", fn world, status ->
    video = Content.get_video!(world.org, world.video.id)
    assert video.mux_status == mux_status_for(status)
    Map.put(world, :video, video)
  end)

  then_("the updated status is reflected in the content list without a page refresh", fn world ->
    world.session
    |> assert_has(css("[data-test=video-status-#{world.video.id}]", text: "Ready"))
    |> assert_has(css("html[data-cm-no-reload]"))

    world
  end)

  then_("the operator can see the error state in the content list", fn world ->
    world.session
    |> assert_has(css("[data-test=video-status-#{world.video.id}]", text: "Error"))
    |> assert_has(css("html[data-cm-no-reload]"))

    world
  end)

  # ---- Thumbnails (Wallaby + local stand-in for the Spaces presigned URL) ---

  given_("a video exists with no portrait or landscape thumbnail uploaded", fn world ->
    video =
      ready_video(world.org,
        title: "Fallback Feature",
        portrait_thumbnail_url: nil,
        landscape_thumbnail_url: nil,
        custom_thumbnail_url: nil
      )

    Map.put(world, :video, video)
  end)

  given_("a video exists with both a portrait and a landscape thumbnail", fn world ->
    video =
      ready_video(world.org,
        title: "Dual Thumbnail Feature",
        portrait_thumbnail_url: "https://cdn.example.test/existing/portrait.png",
        landscape_thumbnail_url: "https://cdn.example.test/existing/landscape.png"
      )

    Map.merge(world, %{video: video, original_video: video})
  end)

  when_("I upload a thumbnail image for that video", fn world ->
    upload_thumbnail(world, "video_landscape_thumbnail")
  end)

  when_("I upload a portrait thumbnail image for that video", fn world ->
    upload_thumbnail(world, "video_portrait_thumbnail")
  end)

  when_("I upload a landscape thumbnail image for that video", fn world ->
    upload_thumbnail(world, "video_landscape_thumbnail")
  end)

  when_("I upload a new landscape thumbnail", fn world ->
    upload_thumbnail(world, "video_landscape_thumbnail")
  end)

  when_("the video is displayed on the viewer site", fn world ->
    Map.put(world, :viewer_thumbnails, viewer_card_thumbnails(world.org, world.video))
  end)

  then_("the thumbnail is stored and associated with the video", fn world ->
    video = Content.get_video!(world.org, world.video.id)
    assert video.landscape_thumbnail_url == world.uploaded_thumbnail_url

    # Reopening the editor shows the stored image, read back from the DB.
    world.session
    |> visit_content(world)
    |> click(css("[data-test=view-video-#{video.id}]"))
    |> click(css("[data-test=edit-video-btn]"))
    |> assert_has(
      css("[data-test=image-upload-preview-video_landscape_thumbnail] img[src='#{world.uploaded_thumbnail_url}']",
        visible: :any
      )
    )

    world
  end)

  then_("the portrait thumbnail is stored and used for poster-style card displays", fn world ->
    video = Content.get_video!(world.org, world.video.id)
    assert video.portrait_thumbnail_url == world.uploaded_thumbnail_url
    assert video.landscape_thumbnail_url == world.video.landscape_thumbnail_url

    thumbs = viewer_card_thumbnails(world.org, video)
    assert thumbs.portrait == world.uploaded_thumbnail_url
    refute thumbs.landscape == world.uploaded_thumbnail_url
    world
  end)

  then_("the landscape thumbnail is stored and used for episode and hero card displays", fn world ->
    video = Content.get_video!(world.org, world.video.id)
    assert video.landscape_thumbnail_url == world.uploaded_thumbnail_url
    assert video.portrait_thumbnail_url == world.video.portrait_thumbnail_url

    thumbs = viewer_card_thumbnails(world.org, video)
    assert thumbs.landscape == world.uploaded_thumbnail_url
    refute thumbs.portrait == world.uploaded_thumbnail_url
    world
  end)

  then_("the player uses the Mux-generated thumbnail at the appropriate aspect dimensions", fn world ->
    playback_id = world.video.mux_playback_id

    assert_mux_smartcrop(world.viewer_thumbnails.portrait, playback_id, {2, 3})
    assert_mux_smartcrop(world.viewer_thumbnails.landscape, playback_id, {16, 9})
    world
  end)

  then_("the portrait thumbnail remains unchanged", fn world ->
    video = Content.get_video!(world.org, world.video.id)
    assert video.portrait_thumbnail_url == world.original_video.portrait_thumbnail_url
    assert video.landscape_thumbnail_url == world.uploaded_thumbnail_url
    world
  end)

  # ---- Tags on a video (Wallaby) -----------------------------------------------

  given_("a video exists", fn world ->
    Map.put(world, :video, ready_video(world.org, title: "Untagged Feature"))
  end)

  given_("a video exists and tags are available", fn world ->
    video = ready_video(world.org, title: "Taggable Feature")
    drama = insert(:tag, organization: world.org, name: "Drama", slug: "drama")
    comedy = insert(:tag, organization: world.org, name: "Comedy", slug: "comedy")
    Map.merge(world, %{video: video, available_tags: [drama, comedy], picked_tag: drama})
  end)

  given_("a video has an associated tag", fn world ->
    video = ready_video(world.org, title: "Tagged Feature")
    tag = insert(:tag, organization: world.org, name: "Classics", slug: "classics")
    insert(:video_tag, organization: world.org, video: video, tag: tag)
    Map.merge(world, %{video: video, video_tag: tag})
  end)

  when_("I add a tag to the video via the tag picker", fn world ->
    tag = world.picked_tag

    session =
      world.session
      |> open_video(world)
      |> click(css("[data-test=add-tag-btn]"))
      |> click(css("[data-test=pick-tag-#{tag.id}]"))
      |> assert_has(css("[data-test=video-tag-#{tag.id}]", text: tag.name))

    Map.put(world, :session, session)
  end)

  when_("I create a new tag and apply it to the video", fn world ->
    # Tag names are stored lowercase, so the new name is already in that form.
    name = "behind the scenes"

    session =
      world.session
      |> open_video(world)
      |> assert_has(css("[data-test=no-tags]"))
      |> click(css("[data-test=add-tag-btn]"))
      |> fill_in(css("[data-test=tag-search-input]"), with: name)
      |> await_has(css("[data-test=create-tag-btn]", text: name))
      |> click(css("[data-test=create-tag-btn]", text: name))
      |> await_has(css("[data-test=video-tags-list]", text: name))

    Map.merge(world, %{session: session, new_tag_name: name})
  end)

  when_("I remove the tag from the video", fn world ->
    tag = world.video_tag

    session =
      world.session
      |> open_video(world)
      |> assert_has(css("[data-test=video-tag-#{tag.id}]"))
      |> click(css("[data-test=remove-tag-#{tag.id}]"))
      |> await_gone(css("[data-test=video-tag-#{tag.id}]"))

    Map.put(world, :session, session)
  end)

  then_("the tag is associated with that video", fn world ->
    tag = world.picked_tag
    assert tag.id in Enum.map(Content.list_video_tags(world.org, world.video), & &1.id)
    world
  end)

  then_("the tag is created in the system", fn world ->
    %{results: tags} = Content.list_tags(world.org, per_page: 100)
    tag = Enum.find(tags, &(&1.name == world.new_tag_name))
    assert tag, "expected tag #{world.new_tag_name} to exist"
    Map.put(world, :created_tag, tag)
  end)

  then_("immediately associated with that video", fn world ->
    tag = world.created_tag
    assert tag.id in Enum.map(Content.list_video_tags(world.org, world.video), & &1.id)

    # Shown in the open detail view without leaving the page.
    assert_has(world.session, css("[data-test=video-tag-#{tag.id}]", text: tag.name))
    world
  end)

  then_("the tag is disassociated from that video", fn world ->
    tag = world.video_tag
    refute tag.id in Enum.map(Content.list_video_tags(world.org, world.video), & &1.id)

    # Only the association goes; the tag itself stays available.
    assert {:ok, %{deleted_at: nil}} = Content.get_tag(world.org, tag.id)
    world
  end)

  # ---- Search and pagination ---------------------------------------------------

  given_("videos exist in the content library", fn world ->
    videos = %{
      ocean_one: ready_video(world.org, title: "Ocean Depths"),
      ocean_two: ready_video(world.org, title: "Life in the Ocean"),
      mountain: ready_video(world.org, title: "Mountain Summit")
    }

    Map.put(world, :search_videos, videos)
  end)

  when_("I type a search query in the search box", fn world ->
    %{mountain: mountain} = world.search_videos

    session =
      world.session
      |> visit_content(world)
      |> assert_has(css("[data-test=view-video-#{mountain.id}]"))
      |> execute_script("document.documentElement.setAttribute('data-cm-no-reload', ''); return true;")
      |> fill_in(css("[data-test=video-search]"), with: "Ocean")

    Map.put(world, :session, session)
  end)

  then_("the video list filters in real time to matching results", fn world ->
    %{ocean_one: one, ocean_two: two, mountain: mountain} = world.search_videos

    world.session
    |> await_gone(css("[data-test=view-video-#{mountain.id}]"))
    |> assert_has(css("[data-test=view-video-#{one.id}]"))
    |> assert_has(css("[data-test=view-video-#{two.id}]"))
    |> assert_has(css("html[data-cm-no-reload]"))

    world
  end)

  given_("more than one page of videos exists", fn world ->
    for n <- 1..26, do: ready_video(world.org, title: "Catalog Entry #{n}")

    %{results: first_page} = Content.list_videos(world.org, search: nil, tag_ids: [], page: 1, per_page: 24)

    session =
      world.session
      |> visit_content(world)
      |> assert_has(css("[data-test=page-next]"))
      |> assert_has(css("[data-test^=view-video-]", count: 24))

    Map.merge(world, %{session: session, first_page_videos: first_page})
  end)

  then_("the next set of videos is displayed", fn world ->
    %{results: second_page} =
      Content.list_videos(world.org, search: nil, tag_ids: [], page: 2, per_page: 24)

    assert second_page != []

    session = assert_has(world.session, css("[data-test=page-prev]"))

    Enum.each(second_page, fn video ->
      assert_has(session, css("[data-test=view-video-#{video.id}]"))
    end)

    assert_has(session, css("[data-test^=view-video-]", count: length(second_page)))
    refute_has(session, css("[data-test=view-video-#{hd(world.first_page_videos).id}]"))
    world
  end)

  # ---- Helpers ------------------------------------------------------------------

  defp ready_video(org, attrs) do
    insert(
      :video,
      Keyword.merge(
        [organization: org, mux_status: "ready", published: true, duration: 600.0],
        attrs
      )
    )
  end

  # The content page tour auto-starts for a new operator; mark it done so
  # its overlay never sits over the controls these steps click.
  defp visit_content(session, world) do
    {:ok, _} = Marquee.Accounts.complete_page_tour(world.operator, world.org, "content")
    visit_settled(session, "/admin/content?org=#{world.org.slug}")
  end

  # Chrome runs with pageLoadStrategy "none", so `visit/2` can return while
  # the previous page is still showing. A marker on the old document proves
  # the new one has replaced it before waiting for the LiveView to connect.
  defp visit_settled(session, path) do
    session
    |> execute_script("document.documentElement.setAttribute('data-cm-stale', ''); return true;")
    |> visit(path)
    |> refute_has(css("html[data-cm-stale]"))
    |> await_live_connect()
  end

  defp open_video(session, world) do
    session
    |> visit_content(world)
    |> click(css("[data-test=view-video-#{world.video.id}]"))
    |> assert_has(css("[data-test=video-tags-panel]"))
  end

  defp scratch_dir do
    dir = Path.join(System.tmp_dir!(), "marquee-cuke-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  # Status words used in the feature map onto Mux asset states.
  defp mux_status_for("uploading"), do: "waiting"
  defp mux_status_for("processing"), do: "preparing"
  defp mux_status_for("ready"), do: "ready"
  defp mux_status_for("error"), do: "errored"

  defp status_label_for("uploading"), do: "Uploading"
  defp status_label_for("processing"), do: "Processing"
  defp status_label_for("ready"), do: "Ready"
  defp status_label_for("error"), do: "Error"

  defp post_mux_webhook(payload) do
    body = Jason.encode!(payload)
    secret = "cuke-mux-webhook-secret"
    timestamp = System.system_time(:second)

    signature =
      :hmac
      |> :crypto.mac(:sha256, secret, "#{timestamp}.#{body}")
      |> Base.encode16(case: :lower)

    previous = Application.fetch_env(:marquee, :mux_webhook_secret)
    Application.put_env(:marquee, :mux_webhook_secret, secret)

    try do
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mux-signature", "t=#{timestamp},v1=#{signature}")
      |> post("/webhooks/mux", body)
    after
      case previous do
        {:ok, value} -> Application.put_env(:marquee, :mux_webhook_secret, value)
        :error -> Application.delete_env(:marquee, :mux_webhook_secret)
      end
    end
  end

  # Drives the edit form's image field: the browser asks for a presigned
  # URL, PUTs the file to it, and the saved video stores the public URL.
  # Spaces is replaced by the Mox stub plus the local stub server.
  defp upload_thumbnail(world, kind) do
    test_pid = self()
    stub = UploadStubServer.start(test_pid)
    image_path = Path.join(scratch_dir(), "#{kind}.png")
    image_bytes = tiny_png()
    File.write!(image_path, image_bytes)

    Mox.set_mox_global()

    Mox.stub(MockSpacesClient, :presign_put, fn opts ->
      key = Keyword.fetch!(opts, :key)
      send(test_pid, {:presign_put, opts})

      {:ok,
       %{
         presigned_url: "#{stub.base_url}/#{key}",
         public_url: "https://cdn.example.test/#{key}",
         key: key,
         headers: %{}
       }}
    end)

    try do
      session =
        world.session
        |> visit_content(world)
        |> click(css("[data-test=view-video-#{world.video.id}]"))
        |> click(css("[data-test=edit-video-btn]"))
        |> attach_file(css("[data-test=image-upload-input-#{kind}]", visible: :any), path: image_path)

      assert_receive {:presign_put, opts}, 10_000
      key = Keyword.fetch!(opts, :key)
      assert Keyword.fetch!(opts, :content_type) == "image/png"
      assert String.starts_with?(key, "org/#{world.org.id}/#{kind}/")

      expected_path = "/" <> key
      assert_receive {:upload_stub_received, _handler, ^expected_path, body}, 10_000
      assert body == image_bytes

      public_url = "https://cdn.example.test/#{key}"

      session =
        session
        |> assert_has(css("[data-test=image-upload-preview-#{kind}] img[src='#{public_url}']", visible: :any))
        |> click(css("[data-test=save-video-btn]"))
        |> assert_has(css("[data-test=edit-video-btn]"))

      Map.merge(world, %{session: session, uploaded_thumbnail_url: public_url})
    after
      Mox.set_mox_private()
      UploadStubServer.stop(stub)
    end
  end

  # 1x1 transparent PNG.
  defp tiny_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )
  end

  # Signs a subscribed viewer in (in a separate browser) and reads the
  # image URL each card variant renders for `video` on the home page.
  defp viewer_card_thumbnails(org, video) do
    poster_row = insert(:row, organization: org, title: "Poster Row", card_variant: "poster_portrait")
    episode_row = insert(:row, organization: org, title: "Episode Row", card_variant: "landscape_episode")
    insert(:row_item, organization: org, row: poster_row, video: video, position: 0)
    insert(:row_item, organization: org, row: episode_row, video: video, position: 0)

    viewer = insert(:subscribed_viewer, organization: org)
    {encoded_token, viewer_token} = ViewerToken.build_magic_link_token(viewer)
    Repo.insert!(viewer_token)

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    try do
      session
      |> visit("/magic-link/#{encoded_token}?org=#{org.slug}")
      |> assert_has(css("[data-test=viewer-sign-out]"))
      |> visit("/?org=#{org.slug}")
      |> assert_has(css("[data-test=content-row-#{poster_row.id}] [data-test=sv-card-#{video.id}] img", visible: :any, minimum: 1))
      |> assert_has(css("[data-test=content-row-#{episode_row.id}] [data-test=sv-card-#{video.id}] img", visible: :any, minimum: 1))

      %{
        portrait: card_image_src(session, poster_row, video),
        landscape: card_image_src(session, episode_row, video)
      }
    after
      Wallaby.end_session(session)
    end
  end

  # A row can render the same card more than once (e.g. responsive
  # variants); every copy must show the same image.
  defp card_image_src(session, row, video) do
    srcs =
      session
      |> all(css("[data-test=content-row-#{row.id}] [data-test=sv-card-#{video.id}] img", visible: :any))
      |> Enum.map(&Element.attr(&1, "src"))
      |> Enum.uniq()

    assert [src] = srcs, "expected one thumbnail URL for the card, got #{inspect(srcs)}"
    src
  end

  defp assert_mux_smartcrop(url, playback_id, {ratio_w, ratio_h}) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")

    assert uri.host == "image.mux.com", "expected a Mux thumbnail URL, got #{url}"
    assert uri.path == "/#{playback_id}/thumbnail.webp"
    assert query["fit_mode"] == "smartcrop"

    width = String.to_integer(query["width"])
    height = String.to_integer(query["height"])
    assert width * ratio_h == height * ratio_w,
           "expected #{ratio_w}:#{ratio_h} dimensions, got #{width}x#{height}"
  end

  # The server can take longer than Wallaby's default wait to process an
  # event while the suite shares the machine with other browser runs.
  # Polls for up to 15s before failing with Wallaby's own message.
  defp await_gone(session, query, timeout_ms \\ 15_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_gone_until(session, query, deadline)
  end

  defp await_gone_until(session, query, deadline) do
    cond do
      not has?(session, query) -> session
      System.monotonic_time(:millisecond) >= deadline -> refute_has(session, query)
      true ->
        Process.sleep(250)
        await_gone_until(session, query, deadline)
    end
  end

  defp await_has(session, query, timeout_ms \\ 15_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_has_until(session, query, deadline)
  end

  defp await_has_until(session, query, deadline) do
    cond do
      has?(session, query) -> session
      System.monotonic_time(:millisecond) >= deadline -> assert_has(session, query)
      true ->
        Process.sleep(250)
        await_has_until(session, query, deadline)
    end
  end
end
