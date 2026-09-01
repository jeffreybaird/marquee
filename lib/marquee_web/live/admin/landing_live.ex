defmodule MarqueeWeb.Admin.LandingLive do
  @moduledoc """
  Admin editor for the configurable marketing landing page.

  Operators can add, edit, reorder, hide, and delete landing sections.
  Each section type has its own config form. On first visit, if the org has
  no sections, a default starter page is seeded.

  Events: add_section, edit_section, cancel_edit, save_section, delete_section,
  toggle_visibility, move_up, move_down, faq_add_item, faq_remove_item
  Route: /admin/landing
  """

  use MarqueeWeb, :live_view

  alias Marquee.Accounts
  alias Marquee.Content
  alias Marquee.Events
  alias Marquee.LandingPage
  alias Marquee.LandingPage.LandingSection

  require Logger

  @section_type_options [
    {"Hero video", "hero_video"},
    {"Hero image", "hero_image"},
    {"Hero slider (existing carousel)", "hero_slider"},
    {"Marketing copy", "marketing_copy"},
    {"Content row", "content_row"},
    {"Plan display", "plan_display"},
    {"Header text", "header_text"},
    {"FAQ", "faq"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    can_manage = Accounts.can_manage_content?(scope)

    if connected?(socket), do: Events.subscribe(org.id)

    # Seed defaults on first visit so the operator has something to edit.
    _ = LandingPage.seed_default_landing_page(scope)

    {:ok,
     socket
     |> assign(:page_title, "Landing Page")
     |> assign(:can_manage, can_manage)
     |> assign(:section_type_options, @section_type_options)
     |> assign(:editing_section, nil)
     |> assign(:edit_form, %{})
     |> assign(:edit_error, nil)
     |> assign(:collections, list_collections(org))
     |> assign(:show_video_picker, false)
     |> assign(:video_picker_tab, :existing)
     |> assign(:available_videos, [])
     |> assign(:upload_file, nil)
     |> assign(:uploading, false)
     |> assign(:upload_percent, 0)
     |> load_sections()}
  end

  @impl true
  def handle_event("add_section", %{"section_type" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_section", %{"section_type" => type_str}, socket) do
    scope = socket.assigns.current_scope
    type = String.to_existing_atom(type_str)

    attrs = %{
      section_type: type,
      visible: true,
      config: default_config_for(type)
    }

    case LandingPage.create_landing_section(scope, attrs) do
      {:ok, section} ->
        {:noreply,
         socket
         |> load_sections()
         |> open_editor(section)
         |> put_flash(:info, "Section added.")}

      {:error, :validation, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not add section: #{format_errors(changeset)}")}
    end
  end

  def handle_event("edit_section", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case LandingPage.get_landing_section(org, id) do
      {:ok, section} -> {:noreply, open_editor(socket, section)}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Section not found.")}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_section: nil, edit_form: %{}, edit_error: nil)}
  end

  def handle_event("save_section", params, socket) do
    scope = socket.assigns.current_scope
    section = socket.assigns.editing_section

    if section do
      attrs = build_save_attrs(section, params)

      case LandingPage.update_landing_section(scope, section, attrs) do
        {:ok, _updated} ->
          {:noreply,
           socket
           |> load_sections()
           |> assign(editing_section: nil, edit_form: %{}, edit_error: nil)
           |> put_flash(:info, "Section saved.")}

        {:error, :validation, changeset} ->
          {:noreply, assign(socket, edit_error: format_errors(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_section", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case LandingPage.get_landing_section(org, id) do
      {:ok, section} ->
        {:ok, _} = LandingPage.delete_landing_section(scope, section)

        {:noreply,
         socket
         |> load_sections()
         |> maybe_close_editor(id)
         |> put_flash(:info, "Section deleted.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Section not found.")}
    end
  end

  def handle_event("toggle_visibility", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case LandingPage.get_landing_section(org, id) do
      {:ok, section} ->
        {:ok, _} =
          LandingPage.update_landing_section(scope, section, %{visible: !section.visible})

        {:noreply, load_sections(socket)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("move_up", %{"id" => id}, socket), do: reorder(socket, id, :up)
  def handle_event("move_down", %{"id" => id}, socket), do: reorder(socket, id, :down)

  def handle_event("faq_add_item", _params, socket) do
    case socket.assigns.editing_section do
      %LandingSection{section_type: :faq} ->
        items = (socket.assigns.edit_form["items"] || []) ++ [%{"question" => "", "answer" => ""}]
        form = Map.put(socket.assigns.edit_form, "items", items)
        {:noreply, assign(socket, edit_form: form)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("faq_remove_item", %{"index" => index}, socket) do
    case socket.assigns.editing_section do
      %LandingSection{section_type: :faq} ->
        index = String.to_integer(index)
        items = socket.assigns.edit_form["items"] || []
        new_items = List.delete_at(items, index)
        form = Map.put(socket.assigns.edit_form, "items", new_items)
        {:noreply, assign(socket, edit_form: form)}

      _ ->
        {:noreply, socket}
    end
  end

  # ── Video picker (hero_video section) ─────────────────────────────────

  def handle_event("open_video_picker", _params, socket) do
    {:noreply, open_picker(socket)}
  end

  def handle_event("close_video_picker", _params, socket) do
    if socket.assigns.uploading do
      {:noreply, socket}
    else
      {:noreply, reset_picker(socket)}
    end
  end

  def handle_event("video_picker_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :video_picker_tab, String.to_existing_atom(tab))}
  end

  def handle_event("select_existing_video", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization

    case Content.get_video(org, video_id) do
      {:ok, %{mux_playback_id: pid}} when is_binary(pid) and pid != "" ->
        form =
          socket.assigns.edit_form
          |> Map.put("video_playback_id", pid)
          |> Map.put("video_url", "")
          |> Map.delete("pending_video_id")

        {:noreply, socket |> assign(:edit_form, form) |> reset_picker()}

      {:ok, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "That video isn't ready yet (no Mux playback ID). Pick a processed one."
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  def handle_event("files_selected", %{"files" => [file | _]}, socket) do
    %{"client_id" => cid, "name" => name} = file
    title = name |> Path.rootname() |> String.replace(~r/[_\-\.]+/, " ") |> String.trim()
    {:noreply, assign(socket, :upload_file, %{client_id: cid, name: name, title: title})}
  end

  def handle_event("submit_upload", params, socket) do
    scope = socket.assigns.current_scope
    file = socket.assigns.upload_file

    if is_nil(file) do
      {:noreply, put_flash(socket, :error, "Select a file first.")}
    else
      title =
        params
        |> Map.get("title", file.title)
        |> to_string()
        |> String.trim()

      title = if title == "", do: file.title, else: title

      case Content.create_upload_url(scope, %{title: title, description: ""},
             current_origin: socket.assigns.current_origin
           ) do
        {:ok, %{video: video, upload_url: url}} ->
          queue = [
            %{client_id: file.client_id, video_id: video.id, upload_url: url, title: title}
          ]

          {:noreply,
           socket
           |> assign(uploading: true, upload_percent: 0)
           |> push_event("start_multi_upload", %{queue: queue})}

        {:error, :mux_error, reason} ->
          Logger.error("Landing hero upload initiation failed",
            organization_id: scope.organization.id,
            user_id: scope.user.id,
            title: title,
            reason: inspect(reason)
          )

          {:noreply,
           put_flash(
             socket,
             :error,
             "Mux could not start this upload. Your Mux account may have reached an asset or upload limit."
           )}

        {:error, :validation, _} ->
          {:noreply, put_flash(socket, :error, "Invalid title for upload.")}
      end
    end
  end

  def handle_event("upload_progress", %{"percent" => pct}, socket) do
    {:noreply, assign(socket, :upload_percent, pct)}
  end

  def handle_event("upload_complete", %{"video_id" => video_id}, socket) do
    # Record pending video id on the section config. When Mux webhook
    # fires `video_ready`, we'll patch in the playback_id. Viewer
    # renderer also resolves video_id → mux_playback_id at render time.
    form =
      socket.assigns.edit_form
      |> Map.put("pending_video_id", video_id)
      |> Map.put("video_url", "")

    {:noreply,
     socket
     |> assign(:edit_form, form)
     |> reset_picker()
     |> put_flash(
       :info,
       "Upload complete. Mux is processing the video — playback ID will fill in automatically."
     )}
  end

  def handle_event("upload_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(uploading: false, upload_percent: 0, upload_file: nil)
     |> put_flash(:error, "Upload failed: #{error}")}
  end

  # Mux webhook fired — if any landing section is waiting on this video,
  # patch its config with the real playback_id.
  @impl true
  def handle_info({:marquee_event, {:video_ready, video}, _scope}, socket) do
    socket = patch_pending_video(socket, video)
    {:noreply, socket}
  end

  def handle_info({:marquee_event, _event, _scope}, socket), do: {:noreply, socket}

  ## --- helpers ----------------------------------------------------------

  defp open_picker(socket) do
    org = socket.assigns.organization
    %{results: all_videos} = Content.list_videos(org, per_page: 100)

    assign(socket,
      show_video_picker: true,
      video_picker_tab: :existing,
      available_videos: all_videos
    )
  end

  defp reset_picker(socket) do
    assign(socket,
      show_video_picker: false,
      video_picker_tab: :existing,
      available_videos: [],
      upload_file: nil,
      uploading: false,
      upload_percent: 0
    )
  end

  defp patch_pending_video(socket, %{id: video_id, mux_playback_id: pid, organization_id: org_id})
       when is_binary(pid) and pid != "" do
    if socket.assigns.organization.id != org_id do
      socket
    else
      scope = socket.assigns.current_scope

      socket.assigns.sections
      |> Enum.filter(fn s ->
        s.section_type == :hero_video and
          Map.get(s.config || %{}, "pending_video_id") == video_id
      end)
      |> Enum.reduce(socket, &apply_pending_video_update(&1, &2, scope, pid))
      |> maybe_refresh_edit_form(video_id, pid)
    end
  end

  defp patch_pending_video(socket, _), do: socket

  defp maybe_refresh_edit_form(socket, video_id, pid) do
    if Map.get(socket.assigns.edit_form, "pending_video_id") == video_id do
      form =
        socket.assigns.edit_form
        |> Map.put("video_playback_id", pid)
        |> Map.delete("pending_video_id")

      assign(socket, :edit_form, form)
    else
      socket
    end
  end

  defp apply_pending_video_update(section, acc, scope, pid) do
    new_config =
      section.config
      |> Map.put("video_playback_id", pid)
      |> Map.delete("pending_video_id")

    case LandingPage.update_landing_section(scope, section, %{config: new_config}) do
      {:ok, _} -> load_sections(acc)
      _ -> acc
    end
  end

  defp load_sections(socket) do
    org = socket.assigns.organization
    %{results: sections} = LandingPage.list_landing_sections_admin(org, per_page: 100)
    assign(socket, sections: sections)
  end

  defp list_collections(org) do
    %{results: collections} = Content.list_collections(org)
    collections
  end

  defp open_editor(socket, %LandingSection{} = section) do
    socket
    |> assign(:editing_section, section)
    |> assign(:edit_form, section.config || %{})
    |> assign(:edit_error, nil)
  end

  defp maybe_close_editor(socket, id) do
    case socket.assigns.editing_section do
      %LandingSection{id: ^id} -> assign(socket, editing_section: nil, edit_form: %{})
      _ -> socket
    end
  end

  defp reorder(socket, id, direction) do
    scope = socket.assigns.current_scope
    sections = socket.assigns.sections
    index = Enum.find_index(sections, &(&1.id == id))

    cond do
      is_nil(index) ->
        {:noreply, socket}

      direction == :up and index == 0 ->
        {:noreply, socket}

      direction == :down and index == length(sections) - 1 ->
        {:noreply, socket}

      true ->
        new_index = if direction == :up, do: index - 1, else: index + 1
        reordered = swap(sections, index, new_index)
        ordered_ids = Enum.map(reordered, & &1.id)
        :ok = LandingPage.reorder_landing_sections(scope, ordered_ids)
        {:noreply, load_sections(socket)}
    end
  end

  defp swap(list, i, j) do
    list
    |> List.replace_at(i, Enum.at(list, j))
    |> List.replace_at(j, Enum.at(list, i))
  end

  ## ── Default config for new sections ─────────────────────────────────

  defp default_config_for(:hero_video) do
    %{
      "video_url" => "",
      "video_playback_id" => "",
      "fallback_image_url" => "",
      "headline" => "Welcome",
      "subheadline" => "",
      "cta_text" => "Get started",
      "cta_link" => "/subscribe",
      "overlay_opacity" => 0.5
    }
  end

  defp default_config_for(:hero_image) do
    %{
      "image_url" => "https://placehold.co/1920x1080",
      "headline" => "Welcome",
      "subheadline" => "",
      "cta_text" => "Get started",
      "cta_link" => "/subscribe",
      "overlay_opacity" => 0.5
    }
  end

  defp default_config_for(:hero_slider), do: %{"use_existing_hero" => true}

  defp default_config_for(:marketing_copy) do
    %{
      "headline" => "Why subscribe",
      "body" => "Tell visitors why they should sign up.",
      "cta_text" => "Subscribe",
      "cta_link" => "/subscribe",
      "text_alignment" => "center"
    }
  end

  defp default_config_for(:content_row) do
    %{"title" => "Featured", "source_type" => "recent", "max_items" => 8}
  end

  defp default_config_for(:plan_display) do
    %{"headline" => "Choose your plan", "subheadline" => "Cancel anytime."}
  end

  defp default_config_for(:header_text) do
    %{"headline" => "Section heading", "size" => "large", "text_alignment" => "center"}
  end

  defp default_config_for(:faq) do
    %{
      "headline" => "Frequently asked questions",
      "items" => [%{"question" => "Can I cancel anytime?", "answer" => "Yes."}]
    }
  end

  ## ── Build save attrs from form params ───────────────────────────────

  defp build_save_attrs(%LandingSection{section_type: :faq} = section, params) do
    items = parse_faq_items(params["faq"] || %{})

    config =
      (section.config || %{})
      |> Map.put("headline", params["headline"])
      |> Map.put("items", items)

    %{config: config, visible: visible_param(params)}
  end

  defp build_save_attrs(%LandingSection{section_type: :content_row}, params) do
    config = %{
      "title" => params["title"],
      "source_type" => params["source_type"],
      "source_id" => empty_to_nil(params["source_id"]),
      "max_items" => parse_int(params["max_items"]) || 8
    }

    %{config: config, visible: visible_param(params)}
  end

  defp build_save_attrs(%LandingSection{section_type: type}, params) do
    config =
      params
      |> Map.drop(["_target", "visible", "_csrf_token"])
      |> coerce_overlay_opacity(type)
      |> coerce_use_existing_hero(type)
      |> coerce_show_flags(type)

    %{config: config, visible: visible_param(params)}
  end

  @show_flag_keys ~w(show_headline show_subheadline show_cta)

  defp coerce_show_flags(map, type) when type in [:hero_video, :hero_image] do
    Enum.reduce(@show_flag_keys, map, fn key, acc ->
      case Map.get(acc, key) do
        "true" -> Map.put(acc, key, true)
        "false" -> Map.put(acc, key, false)
        true -> acc
        false -> acc
        nil -> Map.put(acc, key, true)
        _ -> Map.put(acc, key, true)
      end
    end)
  end

  defp coerce_show_flags(map, _type), do: map

  defp coerce_overlay_opacity(map, type) when type in [:hero_video, :hero_image] do
    case map["overlay_opacity"] do
      nil -> map
      "" -> Map.put(map, "overlay_opacity", 0.5)
      v when is_binary(v) -> Map.put(map, "overlay_opacity", parse_float(v) || 0.5)
      _ -> map
    end
  end

  defp coerce_overlay_opacity(map, _type), do: map

  defp coerce_use_existing_hero(map, :hero_slider) do
    Map.put(map, "use_existing_hero", map["use_existing_hero"] in ["true", true, "on"])
  end

  defp coerce_use_existing_hero(map, _type), do: map

  defp parse_faq_items(%{} = faq_params) do
    faq_params
    |> Enum.sort_by(fn {k, _} -> parse_int(k) || 0 end)
    |> Enum.map(fn {_, item} -> %{"question" => item["question"], "answer" => item["answer"]} end)
    |> Enum.reject(fn item -> item["question"] in [nil, ""] and item["answer"] in [nil, ""] end)
  end

  defp visible_param(%{"visible" => v}) when v in ["true", "on", true], do: true
  defp visible_param(%{"visible" => _}), do: false
  defp visible_param(_), do: true

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(v), do: v

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {int, _} -> int
      _ -> nil
    end
  end

  defp parse_float(v) when is_binary(v) do
    case Float.parse(v) do
      {float, _} -> float
      _ -> nil
    end
  end

  defp hero_video_status(form) do
    cond do
      is_binary(form["video_playback_id"]) and form["video_playback_id"] != "" -> :playback_set
      is_binary(form["pending_video_id"]) and form["pending_video_id"] != "" -> :pending
      is_binary(form["video_url"]) and form["video_url"] != "" -> :url
      true -> :none
    end
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  ## ── Display helpers ─────────────────────────────────────────────────

  def format_section_type(:hero_video), do: "Hero video"
  def format_section_type(:hero_image), do: "Hero image"
  def format_section_type(:hero_slider), do: "Hero slider"
  def format_section_type(:marketing_copy), do: "Marketing copy"
  def format_section_type(:content_row), do: "Content row"
  def format_section_type(:plan_display), do: "Plan display"
  def format_section_type(:header_text), do: "Header text"
  def format_section_type(:faq), do: "FAQ"

  def section_preview_text(%LandingSection{section_type: :content_row, config: config}),
    do: config["title"] || "Untitled row"

  def section_preview_text(%LandingSection{section_type: :plan_display, config: config}),
    do: config["headline"] || "Plan display"

  def section_preview_text(%LandingSection{section_type: :hero_slider}),
    do: "Existing hero carousel"

  def section_preview_text(%LandingSection{section_type: :faq, config: config}),
    do: config["headline"] || "FAQ"

  def section_preview_text(%LandingSection{config: config}),
    do: config["headline"] || ""

  ## ── Render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <%!-- Persistent MuxUploader hook — lives outside the picker sheet --%>
      <div id="mux-uploader" phx-hook="MuxUploader" class="hidden"></div>

      <.header>
        Landing Page
        <:subtitle>Build the page visitors see before they sign up.</:subtitle>
      </.header>

      <div class="admin-landing-editor mt-6" data-test="landing-editor">
        <div class="admin-section-list space-y-2" data-test="section-list">
          <div
            :for={{section, index} <- Enum.with_index(@sections)}
            class={[
              "admin-section-item flex items-center gap-3 rounded-lg border border-admin-border bg-admin-bg p-3",
              !section.visible && "opacity-60"
            ]}
            data-id={section.id}
            data-test={"section-item-#{section.id}"}
          >
            <div class="flex flex-col">
              <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                phx-click="move_up"
                phx-value-id={section.id}
                disabled={index == 0}
                aria-label="Move section up"
              >
                ▲
              </button>
              <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                phx-click="move_down"
                phx-value-id={section.id}
                disabled={index == length(@sections) - 1}
                aria-label="Move section down"
              >
                ▼
              </button>
            </div>

            <div class="admin-section-info flex-1">
              <div class="font-medium">{format_section_type(section.section_type)}</div>
              <div class="text-sm text-admin-muted">{section_preview_text(section)}</div>
            </div>

            <div class="admin-section-actions flex gap-2">
              <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                phx-click="toggle_visibility"
                phx-value-id={section.id}
                data-test={"toggle-visibility-#{section.id}"}
              >
                {if section.visible, do: "Hide", else: "Show"}
              </button>
              <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
                phx-click="edit_section"
                phx-value-id={section.id}
                data-test={"edit-section-#{section.id}"}
              >
                Edit
              </button>
              <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-error hover:bg-admin-card"
                phx-click="delete_section"
                phx-value-id={section.id}
                data-confirm="Delete this section?"
                data-test={"delete-section-#{section.id}"}
              >
                Delete
              </button>
            </div>
          </div>

          <div
            :if={@sections == []}
            class="rounded-lg border border-dashed border-admin-border p-6 text-center text-admin-muted"
            data-test="empty-state"
          >
            No landing sections yet. Add one below.
          </div>
        </div>

        <div class="admin-add-section mt-4" data-test="add-section">
          <form phx-change="add_section" id="add-section-form">
            <select
              name="section_type"
              class="rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              data-test="add-section-select"
            >
              <option value="">+ Add section…</option>
              <option :for={{label, value} <- @section_type_options} value={value}>{label}</option>
            </select>
          </form>
        </div>

        <div
          :if={@editing_section}
          class="mt-6 rounded-lg border border-admin-border bg-admin-card p-4"
          data-test="section-editor"
        >
          <h3 class="font-semibold mb-3">
            Edit {format_section_type(@editing_section.section_type)}
          </h3>

          <p :if={@edit_error} class="text-error text-sm mb-2" data-test="edit-error">
            {@edit_error}
          </p>

          <.section_form
            section={@editing_section}
            form={@edit_form}
            collections={@collections}
          />
        </div>
      </div>

      <MarqueeWeb.Components.AdminUI.admin_sheet
        id="landing-video-picker"
        open={@show_video_picker}
        title="Pick Hero Video"
        subtitle="Choose a video from your content library or upload a new one to Mux."
        on_close="close_video_picker"
      >
        <div class="mb-4 flex gap-1 rounded-lg bg-admin-bg p-1" role="tablist">
          <button
            type="button"
            phx-click="video_picker_tab"
            phx-value-tab="existing"
            role="tab"
            aria-selected={to_string(@video_picker_tab == :existing)}
            class={[
              "flex-1 rounded-md px-3 py-1.5 font-ui text-sm font-medium transition-colors",
              if(@video_picker_tab == :existing,
                do: "bg-admin-card text-admin-fg shadow-sm",
                else: "text-admin-muted hover:text-admin-fg"
              )
            ]}
            data-test="landing-picker-tab-existing"
          >
            From Content
          </button>
          <button
            type="button"
            phx-click="video_picker_tab"
            phx-value-tab="upload"
            role="tab"
            aria-selected={to_string(@video_picker_tab == :upload)}
            class={[
              "flex-1 rounded-md px-3 py-1.5 font-ui text-sm font-medium transition-colors",
              if(@video_picker_tab == :upload,
                do: "bg-admin-card text-admin-fg shadow-sm",
                else: "text-admin-muted hover:text-admin-fg"
              )
            ]}
            data-test="landing-picker-tab-upload"
          >
            Upload new
          </button>
        </div>

        <div :if={@video_picker_tab == :existing}>
          <div :if={@available_videos == []} class="py-8 text-center text-admin-muted">
            No videos yet. Switch to <strong>Upload new</strong> to add one.
          </div>
          <div :if={@available_videos != []} class="space-y-2">
            <div
              :for={video <- @available_videos}
              class="flex items-center justify-between rounded-lg border border-admin-border bg-admin-bg px-3 py-2"
            >
              <div class="min-w-0 flex-1">
                <p
                  class="truncate font-body text-sm text-admin-fg"
                  data-test={"landing-video-select-#{video.id}"}
                >
                  {video.title}
                </p>
                <p
                  :if={!video.mux_playback_id || video.mux_playback_id == ""}
                  class="font-mono text-xs text-admin-muted"
                >
                  Processing…
                </p>
              </div>
              <MarqueeWeb.Components.AdminUI.admin_button
                size={:sm}
                phx-click="select_existing_video"
                phx-value-video-id={video.id}
                disabled={!video.mux_playback_id || video.mux_playback_id == ""}
              >
                Select
              </MarqueeWeb.Components.AdminUI.admin_button>
            </div>
          </div>
        </div>

        <div :if={@video_picker_tab == :upload}>
          <div :if={@uploading} class="space-y-2" data-test="landing-upload-progress">
            <p class="font-ui text-sm text-admin-fg">Uploading… {@upload_percent}%</p>
            <div class="h-2 w-full rounded-full bg-admin-bg">
              <div
                class="h-2 rounded-full bg-admin-accent transition-[width] duration-200"
                style={"width: #{@upload_percent}%"}
              >
              </div>
            </div>
            <p class="font-body text-xs text-admin-muted">
              Video bytes go direct to Mux. Don't close this sheet until the upload finishes.
            </p>
          </div>

          <form :if={!@uploading} phx-submit="submit_upload" class="space-y-4">
            <div>
              <label class="block font-ui text-xs font-medium text-admin-muted mb-1">
                Video file
              </label>
              <input
                type="file"
                accept="video/*"
                data-test="upload-file"
                id="landing-upload-file"
                class="block w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg file:mr-3 file:rounded file:border-0 file:bg-admin-accent file:px-3 file:py-1 file:font-ui file:text-sm file:font-medium file:text-admin-on-accent hover:file:brightness-110"
              />
            </div>

            <div :if={@upload_file}>
              <label class="block font-ui text-xs font-medium text-admin-muted mb-1">Title</label>
              <input
                type="text"
                name="title"
                value={@upload_file.title}
                placeholder={@upload_file.name}
                class="w-full rounded-md border border-admin-border bg-admin-bg px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                data-test="landing-upload-title"
              />
            </div>

            <div
              :if={@upload_file == nil}
              class="py-4 text-center text-admin-muted font-body text-sm"
            >
              Choose a video file to continue.
            </div>

            <div :if={@upload_file} class="flex justify-end">
              <MarqueeWeb.Components.AdminUI.admin_button
                type="submit"
                size={:sm}
                data-test="landing-upload-submit"
                phx-disable-with="Starting…"
              >
                Upload & use
              </MarqueeWeb.Components.AdminUI.admin_button>
            </div>
          </form>
        </div>
      </MarqueeWeb.Components.AdminUI.admin_sheet>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  ## ── Section forms ───────────────────────────────────────────────────

  attr :section, :map, required: true
  attr :form, :map, required: true
  attr :collections, :list, required: true

  defp section_form(%{section: %{section_type: :hero_video}} = assigns) do
    ~H"""
    <form phx-submit="save_section" class="space-y-3">
      <.text_input name="headline" label="Headline" value={@form["headline"]} />
      <.show_field_toggle name="show_headline" label="headline" checked={@form["show_headline"]} />
      <.text_input name="subheadline" label="Subheadline" value={@form["subheadline"]} />
      <.show_field_toggle
        name="show_subheadline"
        label="subheadline"
        checked={@form["show_subheadline"]}
      />

      <div class="rounded-md border border-admin-border bg-admin-bg p-3 space-y-2">
        <div class="flex items-center justify-between gap-3">
          <div class="min-w-0">
            <p class="font-ui text-sm font-medium text-admin-fg">Video source</p>
            <p
              :if={hero_video_status(@form) == :playback_set}
              class="font-mono text-xs text-admin-muted truncate"
            >
              Mux playback ID: {@form["video_playback_id"]}
            </p>
            <p :if={hero_video_status(@form) == :pending} class="font-mono text-xs text-admin-muted">
              Upload pending — Mux is processing…
            </p>
            <p
              :if={hero_video_status(@form) == :url}
              class="font-mono text-xs text-admin-muted truncate"
            >
              URL: {@form["video_url"]}
            </p>
            <p :if={hero_video_status(@form) == :none} class="font-body text-xs text-admin-muted">
              No video chosen.
            </p>
          </div>
          <MarqueeWeb.Components.AdminUI.admin_button
            type="button"
            size={:sm}
            variant={:secondary}
            phx-click="open_video_picker"
            data-test="landing-open-video-picker"
          >
            {if hero_video_status(@form) == :none, do: "Pick video", else: "Change"}
          </MarqueeWeb.Components.AdminUI.admin_button>
        </div>
      </div>

      <input type="hidden" name="video_url" value={@form["video_url"]} />
      <input type="hidden" name="video_playback_id" value={@form["video_playback_id"]} />
      <input type="hidden" name="pending_video_id" value={@form["pending_video_id"]} />

      <.text_input
        name="fallback_image_url"
        label="Fallback image URL"
        value={@form["fallback_image_url"]}
      />
      <.text_input name="cta_text" label="CTA text" value={@form["cta_text"]} />
      <.text_input name="cta_link" label="CTA link" value={@form["cta_link"]} />
      <.show_field_toggle name="show_cta" label="CTA button" checked={@form["show_cta"]} />
      <.number_input
        name="overlay_opacity"
        label="Overlay opacity"
        value={@form["overlay_opacity"]}
        step="0.05"
        min="0"
        max="1"
      />
      <.visible_input value={true} />
      <.form_buttons />
    </form>
    """
  end

  defp section_form(%{section: %{section_type: :hero_image}} = assigns) do
    ~H"""
    <form phx-submit="save_section" class="space-y-3">
      <.text_input name="headline" label="Headline" value={@form["headline"]} />
      <.show_field_toggle name="show_headline" label="headline" checked={@form["show_headline"]} />
      <.text_input name="subheadline" label="Subheadline" value={@form["subheadline"]} />
      <.show_field_toggle
        name="show_subheadline"
        label="subheadline"
        checked={@form["show_subheadline"]}
      />
      <.text_input name="image_url" label="Image URL" value={@form["image_url"]} />
      <.text_input name="cta_text" label="CTA text" value={@form["cta_text"]} />
      <.text_input name="cta_link" label="CTA link" value={@form["cta_link"]} />
      <.show_field_toggle name="show_cta" label="CTA button" checked={@form["show_cta"]} />
      <.number_input
        name="overlay_opacity"
        label="Overlay opacity"
        value={@form["overlay_opacity"]}
        step="0.05"
        min="0"
        max="1"
      />
      <.visible_input value={true} />
      <.form_buttons />
    </form>
    """
  end

  defp section_form(%{section: %{section_type: :hero_slider}} = assigns) do
    ~H"""
    <form phx-submit="save_section" class="space-y-3">
      <label class="flex items-center gap-2">
        <input
          type="checkbox"
          name="use_existing_hero"
          checked={@form["use_existing_hero"] == true}
          class="checkbox"
        />
        <span>Use the existing hero carousel from the catalog</span>
      </label>
      <.visible_input value={true} />
      <.form_buttons />
    </form>
    """
  end

  defp section_form(%{section: %{section_type: :marketing_copy}} = assigns) do
    ~H"""
    <form phx-submit="save_section" class="space-y-3">
      <.text_input name="headline" label="Headline" value={@form["headline"]} />
      <label class="block">
        <span class="block text-sm font-medium mb-1">Body</span>
        <textarea
          name="body"
          rows="4"
          class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
        >{@form["body"]}</textarea>
      </label>
      <.text_input name="cta_text" label="CTA text" value={@form["cta_text"]} />
      <.text_input name="cta_link" label="CTA link" value={@form["cta_link"]} />
      <label class="block">
        <span class="block text-sm font-medium mb-1">Text alignment</span>
        <select
          name="text_alignment"
          class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
        >
          <option value="center" selected={@form["text_alignment"] == "center"}>Center</option>
          <option value="left" selected={@form["text_alignment"] == "left"}>Left</option>
        </select>
      </label>
      <.text_input
        name="background_color"
        label="Background color (CSS)"
        value={@form["background_color"]}
      />
      <.text_input
        name="background_image_url"
        label="Background image URL"
        value={@form["background_image_url"]}
      />
      <.visible_input value={true} />
      <.form_buttons />
    </form>
    """
  end

  defp section_form(%{section: %{section_type: :content_row}} = assigns) do
    ~H"""
    <form phx-submit="save_section" class="space-y-3">
      <.text_input name="title" label="Title" value={@form["title"]} />
      <label class="block">
        <span class="block text-sm font-medium mb-1">Source</span>
        <select
          name="source_type"
          class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
        >
          <option value="recent" selected={@form["source_type"] == "recent"}>Recent videos</option>
          <option value="collection" selected={@form["source_type"] == "collection"}>
            Collection
          </option>
        </select>
      </label>
      <label class="block">
        <span class="block text-sm font-medium mb-1">Collection (when source = collection)</span>
        <select
          name="source_id"
          class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
        >
          <option value="">— select a collection —</option>
          <option
            :for={collection <- @collections}
            value={collection.id}
            selected={@form["source_id"] == collection.id}
          >
            {collection.title}
          </option>
        </select>
      </label>
      <.number_input name="max_items" label="Max items" value={@form["max_items"]} step="1" min="1" />
      <.visible_input value={true} />
      <.form_buttons />
    </form>
    """
  end

  defp section_form(%{section: %{section_type: :plan_display}} = assigns) do
    ~H"""
    <form phx-submit="save_section" class="space-y-3">
      <.text_input name="headline" label="Headline" value={@form["headline"]} />
      <.text_input name="subheadline" label="Subheadline" value={@form["subheadline"]} />
      <p class="text-sm text-admin-muted">
        Plans are auto-populated from your active billing plans.
      </p>
      <.visible_input value={true} />
      <.form_buttons />
    </form>
    """
  end

  defp section_form(%{section: %{section_type: :header_text}} = assigns) do
    ~H"""
    <form phx-submit="save_section" class="space-y-3">
      <.text_input name="headline" label="Headline" value={@form["headline"]} />
      <.text_input name="subheadline" label="Subheadline" value={@form["subheadline"]} />
      <label class="block">
        <span class="block text-sm font-medium mb-1">Size</span>
        <select
          name="size"
          class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
        >
          <option value="small" selected={@form["size"] == "small"}>Small</option>
          <option value="medium" selected={@form["size"] == "medium"}>Medium</option>
          <option value="large" selected={@form["size"] == "large"}>Large</option>
        </select>
      </label>
      <label class="block">
        <span class="block text-sm font-medium mb-1">Alignment</span>
        <select
          name="text_alignment"
          class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
        >
          <option value="center" selected={@form["text_alignment"] == "center"}>Center</option>
          <option value="left" selected={@form["text_alignment"] == "left"}>Left</option>
        </select>
      </label>
      <.visible_input value={true} />
      <.form_buttons />
    </form>
    """
  end

  defp section_form(%{section: %{section_type: :faq}} = assigns) do
    ~H"""
    <form phx-submit="save_section" class="space-y-3">
      <.text_input name="headline" label="Headline" value={@form["headline"]} />

      <div class="space-y-2">
        <div
          :for={{item, index} <- Enum.with_index(@form["items"] || [])}
          class="rounded border border-admin-border p-2"
          data-test={"faq-edit-item-#{index}"}
        >
          <input
            type="text"
            name={"faq[#{index}][question]"}
            value={item["question"]}
            placeholder="Question"
            class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none mb-1"
          />
          <textarea
            name={"faq[#{index}][answer]"}
            rows="2"
            placeholder="Answer"
            class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          >{item["answer"]}</textarea>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-ui text-xs font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg mt-1"
            phx-click="faq_remove_item"
            phx-value-index={index}
          >
            Remove
          </button>
        </div>
      </div>

      <button
        type="button"
        class="inline-flex items-center gap-1.5 rounded-md border border-admin-border bg-admin-card px-3 py-1.5 font-ui text-sm font-medium text-admin-fg hover:border-admin-border"
        phx-click="faq_add_item"
      >
        + Add item
      </button>
      <.visible_input value={true} />
      <.form_buttons />
    </form>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, default: nil

  defp text_input(assigns) do
    ~H"""
    <label class="block">
      <span class="block text-sm font-medium mb-1">{@label}</span>
      <input
        type="text"
        name={@name}
        value={@value}
        class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
      />
    </label>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :step, :string, default: "1"
  attr :min, :string, default: nil
  attr :max, :string, default: nil

  defp number_input(assigns) do
    ~H"""
    <label class="block">
      <span class="block text-sm font-medium mb-1">{@label}</span>
      <input
        type="number"
        name={@name}
        value={@value}
        step={@step}
        min={@min}
        max={@max}
        class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
      />
    </label>
    """
  end

  attr :value, :any, default: true

  defp visible_input(assigns) do
    ~H"""
    <input type="hidden" name="visible" value={if @value, do: "true", else: "false"} />
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :checked, :any, default: true

  defp show_field_toggle(assigns) do
    assigns = assign(assigns, :checked?, show_field_checked?(assigns.checked))

    ~H"""
    <label class="flex items-center gap-2 font-ui text-sm text-admin-fg">
      <input type="hidden" name={@name} value="false" />
      <input
        type="checkbox"
        name={@name}
        value="true"
        checked={@checked?}
        class="size-4 rounded border-admin-border bg-admin-card text-admin-accent focus:ring-admin-accent"
        data-test={"toggle-#{@name}"}
      />
      <span>Show {@label}</span>
    </label>
    """
  end

  defp show_field_checked?(false), do: false
  defp show_field_checked?("false"), do: false
  defp show_field_checked?(nil), do: true
  defp show_field_checked?(_), do: true

  defp form_buttons(assigns) do
    ~H"""
    <div class="flex gap-2 mt-3">
      <button
        type="submit"
        class="inline-flex items-center gap-1.5 rounded-md bg-admin-accent px-3 py-1.5 font-ui text-sm font-medium text-admin-on-accent hover:brightness-110"
        data-test="save-section"
      >
        Save
      </button>
      <button
        type="button"
        class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 font-ui text-sm font-medium text-admin-muted hover:bg-admin-card hover:text-admin-fg"
        phx-click="cancel_edit"
      >
        Cancel
      </button>
    </div>
    """
  end
end
