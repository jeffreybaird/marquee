defmodule BobineWeb.Admin.ContentLive do
  @moduledoc """
  Video content management. Lists all org videos with search, handles
  direct-to-Mux upload (multi-file), video metadata editing, tag assignment,
  soft delete, and real-time Mux status updates via Events.

  Hooks: MuxUploader (direct upload to Mux)
  Events: search, open_upload, upload_complete, upload_error, view_video,
          edit_video, save_video, delete_video, tag management events
  Route: /admin/content
  """

  use BobineWeb, :live_view
  use BobineWeb.Admin.ImageUploadHandlers

  import BobineWeb.Admin.ContentLive.Components

  alias Bobine.Accounts
  alias Bobine.Content
  alias Bobine.Events
  alias Bobine.Workers.MuxAssetCleanup
  alias BobineWeb.Admin.ImageUploadHandlers

  @impl true
  def allowed_upload_kind?("video_thumbnail"), do: true
  def allowed_upload_kind?(_), do: false

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Events.subscribe(org.id)
    end

    can_manage = Accounts.can_manage_content?(scope)

    {:ok,
     socket
     |> assign(:page_title, "Content")
     |> assign(:search, "")
     |> assign(:show_upload_modal, false)
     |> assign(:upload_files, [])
     |> assign(:uploading, false)
     |> assign(:upload_total, 0)
     |> assign(:upload_completed, 0)
     |> assign(:upload_percent, 0)
     |> assign(:can_manage, can_manage)
     |> assign(:viewing_video, nil)
     |> assign(:video_tags, [])
     |> assign(:all_tags, [])
     |> assign(:editing_video, false)
     |> assign(:show_tag_picker, false)
     |> assign(:tag_search, "")
     |> assign(:row_tag_picker_video_id, nil)
     |> load_videos()}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply, socket |> assign(:search, term) |> load_videos()}
  end

  @impl true
  def handle_event("open_upload", _params, socket) do
    {:noreply,
     assign(socket,
       show_upload_modal: true,
       upload_files: [],
       uploading: false,
       upload_total: 0,
       upload_completed: 0,
       upload_percent: 0
     )}
  end

  @impl true
  def handle_event("close_upload", _params, socket) do
    if socket.assigns.uploading do
      {:noreply, socket}
    else
      {:noreply, assign(socket, show_upload_modal: false, upload_files: [])}
    end
  end

  @impl true
  def handle_event("files_selected", %{"files" => files}, socket) do
    upload_files =
      Enum.map(files, fn %{"client_id" => cid, "name" => name} ->
        title = name |> Path.rootname() |> String.replace(~r/[_\-\.]+/, " ") |> String.trim()
        %{client_id: cid, name: name, title: title}
      end)

    {:noreply, assign(socket, :upload_files, upload_files)}
  end

  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def handle_event("submit_upload", params, socket) do
    titles = params["titles"] || %{}
    scope = socket.assigns.current_scope
    upload_files = socket.assigns.upload_files

    # Build the upload queue: create a Mux upload URL for each file
    upload_queue =
      Enum.reduce_while(upload_files, {:ok, []}, fn file, {:ok, acc} ->
        title = String.trim(Map.get(titles, file.client_id, file.title))
        title = if title == "", do: file.title, else: title

        case Content.create_upload_url(scope, %{title: title, description: ""},
               current_origin: socket.assigns.current_origin
             ) do
          {:ok, %{video: video, upload_url: url}} ->
            entry = %{
              client_id: file.client_id,
              video_id: video.id,
              upload_url: url,
              title: title
            }

            {:cont, {:ok, acc ++ [entry]}}

          {:error, :mux_error, reason} ->
            Logger.error("Admin upload initiation failed",
              organization_id: scope.organization.id,
              user_id: scope.user.id,
              title: title,
              reason: inspect(reason)
            )

            {:halt, {:error, :mux_error, reason}}

          {:error, :validation, _changeset} ->
            {:halt, {:error, :validation_failed, title}}
        end
      end)

    case upload_queue do
      {:ok, queue} when queue != [] ->
        {:noreply,
         socket
         |> assign(
           uploading: true,
           upload_total: length(queue),
           upload_completed: 0,
           upload_percent: 0
         )
         |> push_event("start_multi_upload", %{queue: queue})
         |> load_videos()}

      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "No files to upload.")}

      {:error, :mux_error, reason} ->
        {:noreply, put_flash(socket, :error, mux_upload_error_message(reason))}

      {:error, :validation_failed, title} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Invalid title for \"#{title}\". Please provide a valid title."
         )}
    end
  end

  @impl true
  def handle_event("upload_progress", %{"video_id" => _id, "percent" => pct}, socket) do
    {:noreply, assign(socket, :upload_percent, pct)}
  end

  @impl true
  def handle_event("upload_complete", %{"video_id" => _id}, socket) do
    completed = socket.assigns.upload_completed + 1
    total = socket.assigns.upload_total

    if completed >= total do
      {:noreply,
       socket
       |> assign(
         show_upload_modal: false,
         uploading: false,
         upload_files: [],
         upload_total: 0,
         upload_completed: 0,
         upload_percent: 0
       )
       |> put_flash(:info, upload_complete_message(total))
       |> load_videos()}
    else
      {:noreply,
       socket
       |> assign(upload_completed: completed, upload_percent: 0)
       |> load_videos()}
    end
  end

  @impl true
  def handle_event("upload_error", %{"video_id" => _id, "error" => error}, socket) do
    completed = socket.assigns.upload_completed + 1
    total = socket.assigns.upload_total

    if completed >= total do
      {:noreply,
       socket
       |> assign(
         show_upload_modal: false,
         uploading: false,
         upload_files: [],
         upload_total: 0,
         upload_completed: 0,
         upload_percent: 0
       )
       |> put_flash(:error, "Upload failed: #{error}")
       |> load_videos()}
    else
      {:noreply,
       socket
       |> assign(upload_completed: completed, upload_percent: 0)
       |> put_flash(:error, "Upload failed: #{error}")
       |> load_videos()}
    end
  end

  @impl true
  def handle_event("delete_video", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_video(org, id) do
      {:ok, video} ->
        {:ok, _} = Content.delete_video(scope, video)

        if video.mux_asset_id do
          %{"mux_asset_id" => video.mux_asset_id, "organization_id" => org.id}
          |> Bobine.Otel.put_trace_context()
          |> MuxAssetCleanup.new()
          |> Oban.insert()
        end

        {:noreply,
         socket
         |> assign(:viewing_video, nil)
         |> put_flash(:info, "Video deleted.")
         |> load_videos()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  # --- Video detail view ---

  @impl true
  def handle_event("view_video", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_video(org, id) do
      {:ok, video} ->
        tags = Content.list_video_tags(org, video)

        {:noreply,
         socket
         |> ImageUploadHandlers.put_initial_url(
           "video_thumbnail",
           video.id,
           video.custom_thumbnail_url
         )
         |> assign(:viewing_video, video)
         |> assign(:video_tags, tags)
         |> assign(:editing_video, false)
         |> assign(:show_tag_picker, false)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply,
     socket
     |> assign(:viewing_video, nil)
     |> assign(:video_tags, [])
     |> assign(:editing_video, false)
     |> assign(:show_tag_picker, false)}
  end

  @impl true
  def handle_event("edit_video", _params, socket) do
    {:noreply, assign(socket, :editing_video, true)}
  end

  @impl true
  def handle_event("save_video", %{"video" => params}, socket) do
    video = socket.assigns.viewing_video
    scope = socket.assigns.current_scope

    uploaded_thumbnail =
      ImageUploadHandlers.upload_url(socket, "video_thumbnail", video.id)

    params = maybe_put_custom_thumbnail_url(params, uploaded_thumbnail)

    case Content.update_video(scope, video, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:viewing_video, updated)
         |> assign(:editing_video, false)
         |> put_flash(:info, "Video updated.")
         |> load_videos()}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update video.")}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_video, false)}
  end

  # --- Tag management (detail view) ---

  @impl true
  def handle_event("open_tag_picker", _params, socket) do
    org = socket.assigns.organization
    %{results: all_tags} = Content.list_tags(org)
    {:noreply, assign(socket, show_tag_picker: true, all_tags: all_tags, tag_search: "")}
  end

  @impl true
  def handle_event("close_tag_picker", _params, socket) do
    {:noreply, assign(socket, show_tag_picker: false, tag_search: "")}
  end

  @impl true
  def handle_event("search_tags", %{"tag_search" => term}, socket) do
    {:noreply, assign(socket, :tag_search, term)}
  end

  @impl true
  def handle_event("create_and_add_tag", %{"name" => name}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    video = socket.assigns.viewing_video

    case Content.create_tag(scope, %{name: name}) do
      {:ok, tag} ->
        case Content.tag_video(scope, video, tag) do
          {:ok, _} ->
            tags = Content.list_video_tags(org, video)

            {:noreply,
             socket
             |> assign(:video_tags, tags)
             |> assign(:show_tag_picker, false)
             |> assign(:tag_search, "")}

          {:error, _, _} ->
            {:noreply, put_flash(socket, :error, "Tag created but could not be added to video.")}
        end

      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "A tag with that name already exists.")}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Invalid tag name.")}
    end
  end

  @impl true
  def handle_event("add_tag", %{"tag-id" => tag_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    video = socket.assigns.viewing_video

    case Content.get_tag(org, tag_id) do
      {:ok, tag} ->
        case Content.tag_video(scope, video, tag) do
          {:ok, _} ->
            tags = Content.list_video_tags(org, video)

            {:noreply,
             socket
             |> assign(:video_tags, tags)
             |> assign(:show_tag_picker, false)}

          {:error, :already_exists} ->
            {:noreply, put_flash(socket, :error, "Tag already applied.")}

          {:error, _, _} ->
            {:noreply, put_flash(socket, :error, "Failed to add tag.")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tag not found.")}
    end
  end

  @impl true
  def handle_event("remove_tag", %{"tag-id" => tag_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    video = socket.assigns.viewing_video

    case Content.get_tag(org, tag_id) do
      {:ok, tag} ->
        :ok = Content.untag_video(scope, video, tag)
        tags = Content.list_video_tags(org, video)
        {:noreply, assign(socket, :video_tags, tags)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tag not found.")}
    end
  end

  # --- Tag management (list row) ---

  @impl true
  def handle_event("open_row_tag_picker", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    %{results: all_tags} = Content.list_tags(org)

    {:noreply,
     assign(socket,
       row_tag_picker_video_id: video_id,
       all_tags: all_tags,
       tag_search: ""
     )}
  end

  @impl true
  def handle_event("close_row_tag_picker", _params, socket) do
    {:noreply, assign(socket, row_tag_picker_video_id: nil, tag_search: "")}
  end

  @impl true
  def handle_event("row_add_tag", %{"tag-id" => tag_id, "video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    with {:ok, video} <- Content.get_video(org, video_id),
         {:ok, tag} <- Content.get_tag(org, tag_id),
         {:ok, _} <- Content.tag_video(scope, video, tag) do
      {:noreply,
       socket
       |> assign(:row_tag_picker_video_id, nil)
       |> assign(:tag_search, "")
       |> load_videos()}
    else
      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "Tag already applied.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Not found.")}

      {:error, _, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add tag.")}
    end
  end

  @impl true
  def handle_event("row_remove_tag", %{"tag-id" => tag_id, "video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    with {:ok, video} <- Content.get_video(org, video_id),
         {:ok, tag} <- Content.get_tag(org, tag_id) do
      :ok = Content.untag_video(scope, video, tag)

      {:noreply, load_videos(socket)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Not found.")}
    end
  end

  @impl true
  def handle_event("row_create_and_add_tag", %{"name" => name, "video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    with {:ok, video} <- Content.get_video(org, video_id),
         {:ok, tag} <- Content.create_tag(scope, %{name: name}),
         {:ok, _} <- Content.tag_video(scope, video, tag) do
      {:noreply,
       socket
       |> assign(:row_tag_picker_video_id, nil)
       |> assign(:tag_search, "")
       |> load_videos()}
    else
      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "A tag with that name already exists.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Not found.")}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Invalid tag name.")}

      {:error, _, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add tag.")}
    end
  end

  defp maybe_put_custom_thumbnail_url(params, nil), do: params
  defp maybe_put_custom_thumbnail_url(params, ""), do: params

  defp maybe_put_custom_thumbnail_url(params, url) when is_binary(url) do
    Map.put(params, "custom_thumbnail_url", url)
  end

  defp upload_complete_message(1), do: "Upload complete. Processing video..."

  defp upload_complete_message(count),
    do: "All #{count} uploads complete. Processing videos..."

  defp mux_upload_error_message(%{type: type, messages: messages}) do
    base =
      "Mux could not start this upload. Your Mux account may have reached an asset or upload limit."

    details =
      [type | List.wrap(messages)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

    if details == "" do
      base
    else
      "#{base} Details: #{details}"
    end
  end

  defp mux_upload_error_message(reason) when is_binary(reason) do
    "Mux could not start this upload. #{reason}"
  end

  defp mux_upload_error_message(_reason) do
    "Mux could not start this upload. Your Mux account may have reached an asset or upload limit."
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:bobine_event, {:video_ready, video}, _scope}, socket) do
    socket = update_video_in_list(socket, video)

    socket =
      if socket.assigns.viewing_video && socket.assigns.viewing_video.id == video.id do
        assign(socket, :viewing_video, video)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:bobine_event, {:video_errored, video}, _scope}, socket) do
    socket = update_video_in_list(socket, video)

    socket =
      if socket.assigns.viewing_video && socket.assigns.viewing_video.id == video.id do
        assign(socket, :viewing_video, video)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:bobine_event, {:video_upload_initiated, _video}, _scope}, socket) do
    {:noreply, load_videos(socket)}
  end

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, socket}
  end

  defp load_videos(socket) do
    org = socket.assigns.organization
    search = socket.assigns.search
    %{results: videos} = Content.list_videos(org, search: search)
    video_ids = Enum.map(videos, & &1.id)
    videos_tags_map = Content.list_tags_for_videos(org, video_ids)

    socket
    |> assign(:videos, videos)
    |> assign(:videos_tags_map, videos_tags_map)
  end

  defp update_video_in_list(socket, updated_video) do
    videos =
      Enum.map(socket.assigns.videos, fn v ->
        if v.id == updated_video.id, do: updated_video, else: v
      end)

    assign(socket, :videos, videos)
  end
end
