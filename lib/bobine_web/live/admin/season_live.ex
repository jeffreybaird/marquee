defmodule BobineWeb.Admin.SeasonLive do
  @moduledoc """
  Season detail page. Lists episodes in the season and supports two ways
  to add episodes:

    1. Upload new videos directly to Mux. Each successful upload is
       immediately attached to this season as the next episode.
    2. Pick from existing org videos that are not already episodes
       anywhere in this org.

  Episodes can be removed (the underlying video is preserved) and the
  cached `episode_count` on the season is kept in sync by the context.

  Hooks: MuxUploader (direct upload to Mux)
  Route: /admin/series/:series_id/seasons/:season_id
  """

  use BobineWeb, :live_view

  alias Bobine.Accounts
  alias Bobine.Content
  alias Bobine.Content.Episode
  alias Bobine.Events
  alias Bobine.Repo
  alias Bobine.Workers.MuxAssetCleanup

  import Ecto.Query, warn: false

  require Logger

  @impl true
  def mount(%{"series_id" => series_id, "season_id" => season_id}, _session, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    with {:ok, series} <- Content.get_series(org, series_id),
         {:ok, season} <- Content.get_season(org, season_id),
         true <- season.series_id == series.id do
      if connected?(socket) do
        Events.subscribe(org.id)
      end

      can_manage = Accounts.can_manage_content?(scope)

      {:ok,
       socket
       |> assign(:page_title, "#{series.title} — #{season.title}")
       |> assign(:can_manage, can_manage)
       |> assign(:series, series)
       |> assign(:season, season)
       |> assign(:show_upload_modal, false)
       |> assign(:upload_files, [])
       |> assign(:uploading, false)
       |> assign(:upload_total, 0)
       |> assign(:upload_completed, 0)
       |> assign(:upload_percent, 0)
       |> assign(:pending_episode_video_ids, [])
       |> assign(:show_picker, false)
       |> assign(:picker_videos, [])
       |> assign(:selected_video_ids, MapSet.new())
       |> load_episodes()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/admin/series")}
    end
  end

  ## -----------------------------------------------------------------------
  ## Episode removal
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("remove_episode", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    season = socket.assigns.season

    with {:ok, video} <- Content.get_video(org, video_id),
         :ok <- Content.remove_episode(scope, season, video) do
      {:noreply,
       socket
       |> put_flash(:info, "Episode removed.")
       |> reload_season()
       |> load_episodes()}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Episode not found.")}
    end
  end

  ## -----------------------------------------------------------------------
  ## Existing-video picker
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("open_picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_picker, true)
     |> assign(:selected_video_ids, MapSet.new())
     |> load_picker_videos()}
  end

  @impl true
  def handle_event("close_picker", _params, socket) do
    {:noreply,
     assign(socket,
       show_picker: false,
       picker_videos: [],
       selected_video_ids: MapSet.new()
     )}
  end

  @impl true
  def handle_event("toggle_picker_video", %{"video-id" => video_id}, socket) do
    selected = socket.assigns.selected_video_ids

    selected =
      if MapSet.member?(selected, video_id) do
        MapSet.delete(selected, video_id)
      else
        MapSet.put(selected, video_id)
      end

    {:noreply, assign(socket, selected_video_ids: selected)}
  end

  @impl true
  def handle_event("add_selected_episodes", _params, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    season = socket.assigns.season

    selected_ids = MapSet.to_list(socket.assigns.selected_video_ids)

    Enum.each(selected_ids, fn video_id ->
      with {:ok, video} <- Content.get_video(org, video_id) do
        Content.add_episode(scope, season, video)
      end
    end)

    {:noreply,
     socket
     |> assign(show_picker: false, picker_videos: [], selected_video_ids: MapSet.new())
     |> put_flash(:info, "Added #{length(selected_ids)} episode(s).")
     |> reload_season()
     |> load_episodes()}
  end

  ## -----------------------------------------------------------------------
  ## Upload flow (mirrors ContentLive but auto-attaches each video as an episode)
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("open_upload", _params, socket) do
    {:noreply,
     assign(socket,
       show_upload_modal: true,
       upload_files: [],
       uploading: false,
       upload_total: 0,
       upload_completed: 0,
       upload_percent: 0,
       pending_episode_video_ids: []
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
  def handle_event("submit_upload", params, socket) do
    titles = params["titles"] || %{}
    scope = socket.assigns.current_scope
    upload_files = socket.assigns.upload_files

    case build_upload_queue(scope, upload_files, titles, socket.assigns.current_origin) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "No files to upload.")}

      {:ok, queue} ->
        # Each video is attached to the season immediately, so when the upload
        # finishes the episode already exists. Mux processes the bytes async.
        attach_videos_as_episodes(scope, socket.assigns.season, queue)

        pending_ids = Enum.map(queue, & &1.video_id)

        {:noreply,
         socket
         |> assign(
           uploading: true,
           upload_total: length(queue),
           upload_completed: 0,
           upload_percent: 0,
           pending_episode_video_ids: pending_ids
         )
         |> push_event("start_multi_upload", %{queue: queue})
         |> reload_season()
         |> load_episodes()}

      {:error, :mux_error, reason} ->
        {:noreply, put_flash(socket, :error, mux_upload_error_message(reason))}

      {:error, :validation_failed, title} ->
        {:noreply, put_flash(socket, :error, "Invalid title for \"#{title}\".")}
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
         upload_percent: 0,
         pending_episode_video_ids: []
       )
       |> put_flash(:info, "Upload complete. Mux is processing the video(s).")
       |> reload_season()
       |> load_episodes()}
    else
      {:noreply, assign(socket, upload_completed: completed, upload_percent: 0)}
    end
  end

  @impl true
  def handle_event("upload_error", %{"video_id" => video_id, "error" => error}, socket) do
    # Roll back the episode for this video so a failed upload does not leave
    # an orphaned episode pointing at a video that will never become ready.
    rollback_failed_episode(socket, video_id)

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
         upload_percent: 0,
         pending_episode_video_ids: []
       )
       |> put_flash(:error, "Upload failed: #{error}")
       |> reload_season()
       |> load_episodes()}
    else
      {:noreply,
       socket
       |> assign(upload_completed: completed, upload_percent: 0)
       |> put_flash(:error, "One upload failed: #{error}")}
    end
  end

  ## -----------------------------------------------------------------------
  ## Real-time updates
  ## -----------------------------------------------------------------------

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, socket |> reload_season() |> load_episodes()}
  end

  ## -----------------------------------------------------------------------
  ## Render
  ## -----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <BobineWeb.Components.AdminUI.admin_panel
        title={@season.title}
        subtitle={@season.description}
      >
        <:actions>
          <.link
            navigate={~p"/admin/series"}
            class="inline-flex items-center justify-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-text-secondary transition-colors hover:bg-admin-elevated hover:text-admin-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent"
            data-test="back-to-series"
          >
            ← Series
          </.link>
          <.link
            navigate={~p"/admin/analytics/series/#{@series.id}/seasons/#{@season.id}"}
            class="inline-flex items-center justify-center gap-1.5 rounded-md border border-admin-border bg-admin-elevated px-3 py-1.5 font-ui text-sm font-medium text-admin-text-primary transition-colors hover:border-admin-border-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent"
            data-test="view-season-analytics"
          >
            Analytics
          </.link>
          <BobineWeb.Components.AdminUI.admin_button
            :if={@can_manage}
            variant={:secondary}
            size={:sm}
            phx-click="open_picker"
            data-test="add-existing-btn"
          >
            Add Existing Video
          </BobineWeb.Components.AdminUI.admin_button>
          <BobineWeb.Components.AdminUI.admin_button
            :if={@can_manage}
            size={:sm}
            phx-click="open_upload"
            data-test="upload-episode-btn"
          >
            Upload Episode
          </BobineWeb.Components.AdminUI.admin_button>
        </:actions>

        <p class="font-ui text-xs uppercase tracking-wide text-admin-text-muted">
          {@series.title}
        </p>
        <div data-test="season-page-title" class="sr-only">{@season.title}</div>

        <BobineWeb.Components.AdminUI.admin_empty
          :if={@episodes == []}
          title="No episodes yet"
          description="Upload a video or pick from existing videos to get started."
          data_test="episodes-empty"
        />

        <div
          :if={@episodes != []}
          class="overflow-x-auto rounded-lg border border-admin-border bg-admin-surface"
          data-test="episodes-list"
        >
          <table class="w-full font-body text-sm text-admin-text-primary">
            <thead class="border-b border-admin-border bg-admin-elevated font-ui text-xs uppercase tracking-wide text-admin-text-muted">
              <tr>
                <th class="px-4 py-3 text-left">#</th>
                <th class="px-4 py-3 text-left">Episode</th>
                <th class="px-4 py-3 text-left">Status</th>
                <th class="px-4 py-3 text-left">Duration</th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={ep <- @episodes}
                data-test={"episode-row-#{ep.id}"}
                class="border-b border-admin-border-subtle last:border-0"
              >
                <td class="px-4 py-3 font-mono">{ep.episode_number}</td>
                <td class="px-4 py-3">
                  <div class="flex items-center gap-3">
                    <div class="h-14 w-24 flex-shrink-0 overflow-hidden rounded bg-admin-elevated">
                      <img
                        :if={ep.video && ep.video.mux_playback_id}
                        src={"https://image.mux.com/#{ep.video.mux_playback_id}/thumbnail.webp?width=192&height=108"}
                        alt={ep.video.title}
                        class="h-full w-full object-cover"
                      />
                    </div>
                    <div>
                      <div class="font-display font-semibold text-admin-text-primary">
                        {ep.title || (ep.video && ep.video.title)}
                      </div>
                      <div class="font-mono text-xs text-admin-text-muted">
                        {ep.video && ep.video.slug}
                      </div>
                    </div>
                  </div>
                </td>
                <td class="px-4 py-3" data-test={"episode-status-#{ep.id}"}>
                  <.status_badge status={ep.video && ep.video.mux_status} />
                </td>
                <td class="px-4 py-3 font-mono text-admin-text-secondary">
                  {format_duration(ep.video && ep.video.duration)}
                </td>
                <td :if={@can_manage} class="px-4 py-3">
                  <div class="flex justify-end">
                    <BobineWeb.Components.AdminUI.admin_button
                      variant={:danger}
                      size={:sm}
                      phx-click="remove_episode"
                      phx-value-video-id={ep.video_id}
                      data-confirm="Remove this episode? The video will not be deleted."
                      data-test={"remove-episode-#{ep.id}"}
                    >
                      Remove
                    </BobineWeb.Components.AdminUI.admin_button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </BobineWeb.Components.AdminUI.admin_panel>

      <%!-- Persistent MuxUploader hook (must survive sheet re-render) --%>
      <div id="season-mux-uploader" phx-hook="MuxUploader" phx-update="ignore"></div>

      <.upload_sheet
        open={@show_upload_modal}
        upload_files={@upload_files}
        uploading={@uploading}
        upload_total={@upload_total}
        upload_completed={@upload_completed}
        upload_percent={@upload_percent}
      />

      <.video_picker
        open={@show_picker}
        videos={@picker_videos}
        selected_video_ids={@selected_video_ids}
      />
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  ## -----------------------------------------------------------------------
  ## Inline components
  ## -----------------------------------------------------------------------

  attr :open, :boolean, required: true
  attr :upload_files, :list, required: true
  attr :uploading, :boolean, required: true
  attr :upload_total, :integer, required: true
  attr :upload_completed, :integer, required: true
  attr :upload_percent, :integer, required: true

  defp upload_sheet(assigns) do
    ~H"""
    <BobineWeb.Components.AdminUI.admin_sheet
      id="episode-upload-sheet"
      open={@open}
      title="Upload Episode"
      on_close="close_upload"
      data_test="episode-upload-modal"
    >
      <div :if={@uploading} class="space-y-2" data-test="upload-progress-section">
        <p class="font-body text-sm text-admin-text-secondary">
          Uploading {@upload_completed + 1} of {@upload_total}… <span class="font-mono">{@upload_percent}%</span>
        </p>
        <progress
          class="w-full"
          value={@upload_percent}
          max="100"
          data-test="upload-progress"
        >
        </progress>
      </div>

      <div :if={!@uploading && @upload_files == []} data-test="upload-file-picker" class="space-y-4">
        <div>
          <label
            class="mb-1 block font-ui text-sm font-medium text-admin-text-primary"
            for="episode-upload-file"
          >
            Select video files
          </label>
          <input
            type="file"
            id="episode-upload-file"
            name="video_file"
            accept="video/*"
            multiple
            class="w-full rounded-md border border-admin-border bg-admin-elevated px-3 py-2 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
            data-test="upload-file"
          />
        </div>
        <div class="flex justify-end">
          <button
            type="button"
            phx-click="close_upload"
            class="inline-flex items-center justify-center gap-1.5 rounded-md px-4 py-2 font-ui text-sm font-medium text-admin-text-secondary transition-colors hover:bg-admin-elevated hover:text-admin-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent"
          >
            Cancel
          </button>
        </div>
      </div>

      <form
        :if={!@uploading && @upload_files != []}
        id="upload-form"
        phx-submit="submit_upload"
        action="#"
        data-test="upload-form"
        class="space-y-4"
      >
        <p class="font-body text-sm text-admin-text-muted">
          {length(@upload_files)} file(s) selected. Each file becomes one episode.
        </p>

        <div class="space-y-3">
          <div
            :for={file <- @upload_files}
            class="flex items-center gap-3"
            data-test={"upload-file-row-#{file.client_id}"}
          >
            <div
              class="w-32 flex-shrink-0 truncate font-mono text-xs text-admin-text-muted"
              title={file.name}
            >
              {file.name}
            </div>
            <input
              type="text"
              name={"titles[#{file.client_id}]"}
              value={file.title}
              class="flex-1 rounded-md border border-admin-border bg-admin-elevated px-3 py-2 font-body text-sm text-admin-text-primary focus:border-admin-accent focus:outline-none"
              placeholder="Episode title"
              data-test={"upload-title-#{file.client_id}"}
            />
          </div>
        </div>
      </form>

      <:footer>
        <button
          :if={!@uploading && @upload_files != []}
          type="button"
          phx-click="close_upload"
          class="inline-flex items-center justify-center gap-1.5 rounded-md px-4 py-2 font-ui text-sm font-medium text-admin-text-secondary transition-colors hover:bg-admin-elevated hover:text-admin-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent"
        >
          Cancel
        </button>
        <BobineWeb.Components.AdminUI.admin_button
          :if={!@uploading && @upload_files != []}
          type="submit"
          form="upload-form"
          data-test="upload-submit"
        >
          Upload {length(@upload_files)} Episode{if length(@upload_files) > 1, do: "s", else: ""}
        </BobineWeb.Components.AdminUI.admin_button>
      </:footer>
    </BobineWeb.Components.AdminUI.admin_sheet>
    """
  end

  attr :open, :boolean, required: true
  attr :videos, :list, required: true
  attr :selected_video_ids, :any, required: true

  defp video_picker(assigns) do
    assigns = assign(assigns, :selected_count, MapSet.size(assigns.selected_video_ids))

    ~H"""
    <BobineWeb.Components.AdminUI.admin_sheet
      id="episode-video-picker-sheet"
      open={@open}
      title="Add Existing Videos"
      on_close="close_picker"
      data_test="episode-video-picker"
    >
      <div :if={@videos == []} class="py-8 text-center font-body text-sm text-admin-text-muted">
        <p>No unassigned videos available.</p>
        <p class="mt-2">All your videos are already episodes in some season.</p>
      </div>

      <div :if={@videos != []} class="space-y-2">
        <label
          :for={video <- @videos}
          class="flex cursor-pointer items-center gap-3 rounded-lg border border-admin-border bg-admin-elevated p-3 hover:border-admin-border-strong"
          data-test={"picker-video-#{video.id}"}
        >
          <input
            type="checkbox"
            class="size-4 rounded border-admin-border bg-admin-surface accent-admin-accent"
            checked={MapSet.member?(@selected_video_ids, video.id)}
            phx-click="toggle_picker_video"
            phx-value-video-id={video.id}
            data-test={"picker-video-checkbox-#{video.id}"}
          />
          <div class="h-12 w-20 flex-shrink-0 overflow-hidden rounded bg-admin-bg">
            <img
              :if={video.mux_playback_id}
              src={"https://image.mux.com/#{video.mux_playback_id}/thumbnail.webp?width=160&height=96"}
              alt={video.title}
              class="h-full w-full object-cover"
            />
          </div>
          <div class="min-w-0 flex-1">
            <div class="truncate font-display font-semibold text-admin-text-primary">
              {video.title}
            </div>
            <div class="font-mono text-xs text-admin-text-muted">
              {format_duration(video.duration)}
            </div>
          </div>
        </label>
      </div>

      <:footer>
        <span class="mr-auto font-ui text-sm text-admin-text-muted">
          {@selected_count} selected
        </span>
        <button
          type="button"
          phx-click="close_picker"
          class="inline-flex items-center justify-center gap-1.5 rounded-md px-4 py-2 font-ui text-sm font-medium text-admin-text-secondary transition-colors hover:bg-admin-elevated hover:text-admin-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent"
        >
          Cancel
        </button>
        <BobineWeb.Components.AdminUI.admin_button
          phx-click="add_selected_episodes"
          disabled={@selected_count == 0}
          data-test="add-selected-episodes-btn"
        >
          Add Selected
        </BobineWeb.Components.AdminUI.admin_button>
      </:footer>
    </BobineWeb.Components.AdminUI.admin_sheet>
    """
  end

  defp status_badge(assigns) do
    {label, tone_class} =
      case assigns.status do
        "ready" ->
          {"Ready",
           "border-admin-accent bg-admin-accent-subtle text-admin-accent-text"}

        "preparing" ->
          {"Processing", "border-warning/50 bg-warning/10 text-admin-text-primary"}

        "waiting" ->
          {"Waiting", "border-admin-border text-admin-text-muted"}

        "errored" ->
          {"Errored", "border-error/50 bg-error/10 text-admin-text-primary"}

        _ ->
          {"Unknown", "border-admin-border text-admin-text-muted"}
      end

    assigns = assign(assigns, label: label, tone_class: tone_class)

    ~H"""
    <span class={[
      "rounded-full border px-2 py-0.5 font-ui text-xs",
      @tone_class
    ]}>
      {@label}
    </span>
    """
  end

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) when is_number(seconds) do
    minutes = div(trunc(seconds), 60)
    secs = rem(trunc(seconds), 60)

    if minutes >= 60 do
      hours = div(minutes, 60)
      mins = rem(minutes, 60)
      "#{hours}h #{mins}m"
    else
      "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
    end
  end

  defp format_duration(_), do: "—"

  ## -----------------------------------------------------------------------
  ## Private helpers
  ## -----------------------------------------------------------------------

  defp load_episodes(socket) do
    org = socket.assigns.organization
    season = socket.assigns.season
    episodes = Content.list_episodes(org, season)
    assign(socket, :episodes, episodes)
  end

  defp reload_season(socket) do
    org = socket.assigns.organization

    case Content.get_season(org, socket.assigns.season.id) do
      {:ok, season} -> assign(socket, :season, season)
      _ -> socket
    end
  end

  defp load_picker_videos(socket) do
    org = socket.assigns.organization
    %{results: all_videos} = Content.list_videos(org, per_page: 100)

    assigned_ids = assigned_video_ids(org)
    available = Enum.reject(all_videos, &MapSet.member?(assigned_ids, &1.id))

    assign(socket, :picker_videos, available)
  end

  # Returns the set of video IDs that are already episodes anywhere in the org.
  defp assigned_video_ids(%{id: org_id}) do
    Episode
    |> where(organization_id: ^org_id)
    |> select([e], e.video_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp build_upload_queue(scope, upload_files, titles, current_origin) do
    Enum.reduce_while(upload_files, {:ok, []}, fn file, {:ok, acc} ->
      title = String.trim(Map.get(titles, file.client_id, file.title))
      title = if title == "", do: file.title, else: title

      case Content.create_upload_url(scope, %{title: title, description: ""},
             current_origin: current_origin
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
          Logger.error("Season upload initiation failed",
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
  end

  defp attach_videos_as_episodes(scope, season, queue) do
    Enum.each(queue, fn %{video_id: video_id} ->
      with {:ok, video} <- Content.get_video(scope.organization, video_id) do
        Content.add_episode(scope, season, video)
      end
    end)
  end

  defp rollback_failed_episode(socket, video_id) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    season = socket.assigns.season

    with {:ok, video} <- Content.get_video(org, video_id) do
      _ = Content.remove_episode(scope, season, video)
      _ = Content.delete_video(video)

      if video.mux_asset_id do
        %{mux_asset_id: video.mux_asset_id, organization_id: org.id}
        |> MuxAssetCleanup.new()
        |> Oban.insert()
      end
    end
  end

  defp mux_upload_error_message(%{type: type, messages: messages}) do
    base =
      "Mux could not start this upload. Your Mux account may have reached an asset or upload limit."

    details =
      [type | List.wrap(messages)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

    if details == "", do: base, else: "#{base} Details: #{details}"
  end

  defp mux_upload_error_message(reason) when is_binary(reason) do
    "Mux could not start this upload. #{reason}"
  end

  defp mux_upload_error_message(_reason) do
    "Mux could not start this upload."
  end
end
