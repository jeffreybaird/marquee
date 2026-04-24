defmodule BobineWeb.Admin.CatalogLive do
  @moduledoc """
  Homepage catalog builder. Operators manage content rows (curated, collection,
  tag, recent, popular, continue_watching) and hero slide configuration.
  Supports drag-and-drop row reordering, inline row editing, video preview,
  and real-time updates via Events subscription.

  Hooks: Sortable (row reordering)
  Events: reordered, add_row, edit_row, save_row, delete_row, hero config events
  Route: /admin/catalog
  """

  use BobineWeb, :live_view

  alias Bobine.Accounts
  alias Bobine.Catalog
  alias Bobine.Content
  alias Bobine.Events

  import BobineWeb.Admin.CatalogLive.Components

  require Logger

  @source_types [
    {"Curated", "curated"},
    {"Collection", "collection"},
    {"Tag", "tag"},
    {"Recent", "recent"},
    {"Popular", "popular"},
    {"Continue Watching", "continue_watching"},
    {"Series with new seasons (auto-populated)", "new_seasons"},
    {"Popularity (preset row type)", "popularity"},
    {"Tags (preset row type)", "tags"},
    {"Preferences (preset row type)", "preferences"},
    {"Series (preset row type)", "series"},
    {"Creator showcase", "creator_showcase"},
    {"Editorial spotlight", "editorial_spotlight"},
    {"Welcome text block", "welcome_text"}
  ]

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
     |> assign(:page_title, "Catalog")
     |> assign(:can_manage, can_manage)
     |> assign(:show_form, false)
     |> assign(:editing_row, nil)
     |> assign(:form, nil)
     |> assign(:source_types, @source_types)
     |> assign(:collections, [])
     |> assign(:tags, [])
     |> assign(:preview_videos, [])
     |> assign(:selected_row, nil)
     |> assign(:show_video_picker, false)
     |> assign(:available_videos, [])
     |> assign(:row_videos, [])
     # Hero editor state
     |> assign(:hero_row, nil)
     |> assign(:hero_slides, [])
     |> assign(:hero_slide_forms, %{})
     |> assign(:show_hero_video_picker, false)
     |> assign(:hero_available_videos, [])
     |> assign(:hero_save_status, %{})
     |> assign(:hero_collapsed, false)
     |> assign(:hero_expanded_slide, nil)
     |> assign(:hero_picker_tab, :existing)
     |> assign(:hero_upload_file, nil)
     |> assign(:hero_uploading, false)
     |> assign(:hero_upload_percent, 0)
     |> assign(:hero_pending_video_id, nil)
     |> assign(:hero_replacing_slide_id, nil)
     |> load_rows()
     |> load_hero_row()}
  end

  # ── Row events ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("new_row", _params, socket) do
    form =
      Catalog.change_row(%Bobine.Catalog.Row{})
      |> to_form()

    org = socket.assigns.organization
    %{results: collections} = Content.list_collections(org)
    %{results: tags} = Content.list_tags(org)

    {:noreply,
     assign(socket,
       show_form: true,
       editing_row: nil,
       form: form,
       collections: collections,
       tags: tags
     )}
  end

  @impl true
  def handle_event("edit_row", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        form = Catalog.change_row(row) |> to_form()
        %{results: collections} = Content.list_collections(org)
        %{results: tags} = Content.list_tags(org)

        {:noreply,
         assign(socket,
           show_form: true,
           editing_row: row,
           form: form,
           collections: collections,
           tags: tags
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("change_row", %{"row" => params}, socket) do
    base = socket.assigns.editing_row || %Bobine.Catalog.Row{}

    form =
      base
      |> Catalog.change_row(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, editing_row: nil, form: nil, preview_videos: [])}
  end

  @impl true
  def handle_event("save_row", %{"row" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.editing_row do
        nil -> Catalog.create_row(scope, params)
        row -> Catalog.update_row(scope, row, params)
      end

    case result do
      {:ok, _row} ->
        {:noreply,
         socket
         |> assign(show_form: false, editing_row: nil, form: nil, preview_videos: [])
         |> put_flash(:info, "Row saved.")
         |> load_rows()}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_row", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        {:ok, _} = Catalog.delete_row(scope, row)

        {:noreply,
         socket
         |> put_flash(:info, "Row deleted.")
         |> load_rows()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("update_row_variant", %{"row_id" => id, "variant" => variant}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        attrs = %{card_variant: normalize_variant(variant)}

        case Catalog.update_row(scope, row, attrs) do
          {:ok, _} ->
            {:noreply, socket |> load_rows() |> put_flash(:info, "Card variant updated.")}

          {:error, :validation, changeset} ->
            {:noreply, put_flash(socket, :error, format_changeset_errors(changeset))}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("toggle_visibility", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        {:ok, _} = Catalog.update_row(scope, row, %{visible: !row.visible})

        {:noreply,
         socket
         |> load_rows()
         |> load_hero_row()}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("preview_row", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        %{results: videos} = Catalog.resolve_row_content(org, row, per_page: 5)
        {:noreply, assign(socket, selected_row: row, preview_videos: videos)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, selected_row: nil, preview_videos: [])}
  end

  @impl true
  def handle_event("move_up", %{"id" => id}, socket) do
    reorder_row(socket, id, :up)
  end

  @impl true
  def handle_event("move_down", %{"id" => id}, socket) do
    reorder_row(socket, id, :down)
  end

  # ── Curated row item events ────────────────────────────────────────────

  @impl true
  def handle_event("manage_items", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Catalog.get_row(org, id) do
      {:ok, row} ->
        %{results: videos} = Catalog.list_row_items(org, row)

        {:noreply,
         assign(socket,
           selected_row: row,
           row_videos: videos,
           preview_videos: []
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Row not found.")}
    end
  end

  @impl true
  def handle_event("back_from_manage", _params, socket) do
    {:noreply,
     assign(socket,
       selected_row: nil,
       row_videos: [],
       show_video_picker: false,
       available_videos: []
     )}
  end

  @impl true
  def handle_event("open_video_picker", _params, socket) do
    org = socket.assigns.organization
    %{results: all_videos} = Content.list_videos(org, per_page: 100)
    row_video_ids = MapSet.new(socket.assigns.row_videos, & &1.id)
    available = Enum.reject(all_videos, &MapSet.member?(row_video_ids, &1.id))

    {:noreply, assign(socket, show_video_picker: true, available_videos: available)}
  end

  @impl true
  def handle_event("close_video_picker", _params, socket) do
    {:noreply, assign(socket, show_video_picker: false, available_videos: [])}
  end

  @impl true
  def handle_event("add_video_to_row", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    row = socket.assigns.selected_row

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        case Catalog.add_item_to_row(scope, row, video) do
          {:ok, _} ->
            %{results: videos} = Catalog.list_row_items(org, row)

            {:noreply,
             assign(socket,
               row_videos: videos,
               show_video_picker: false,
               available_videos: []
             )}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to add video.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  @impl true
  def handle_event("remove_video_from_row", %{"video-id" => video_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    row = socket.assigns.selected_row

    case Content.get_video(org, video_id) do
      {:ok, video} ->
        :ok = Catalog.remove_item_from_row(scope, row, video)
        %{results: videos} = Catalog.list_row_items(org, row)
        {:noreply, assign(socket, row_videos: videos)}

      _ ->
        {:noreply, put_flash(socket, :error, "Video not found.")}
    end
  end

  # ── Hero events ────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_hero_collapsed", _params, socket) do
    {:noreply, update(socket, :hero_collapsed, &(!&1))}
  end

  @impl true
  def handle_event("expand_hero_slide", %{"slide-id" => slide_id}, socket) do
    current = socket.assigns.hero_expanded_slide

    {:noreply,
     assign(socket, :hero_expanded_slide, if(current == slide_id, do: nil, else: slide_id))}
  end

  @impl true
  def handle_event("create_hero", _params, socket) do
    scope = socket.assigns.current_scope

    case Catalog.create_hero_row(scope, %{}) do
      {:ok, _row} ->
        {:noreply,
         socket
         |> put_flash(:info, "Hero carousel created.")
         |> load_rows()
         |> load_hero_row()}

      {:error, :already_exists} ->
        {:noreply,
         socket
         |> put_flash(:error, "Hero carousel already exists.")
         |> load_hero_row()}
    end
  end

  @impl true
  def handle_event("toggle_hero_visibility", _params, socket) do
    scope = socket.assigns.current_scope
    hero_row = socket.assigns.hero_row

    if hero_row do
      {:ok, _} = Catalog.update_row(scope, hero_row, %{visible: !hero_row.visible})

      {:noreply,
       socket
       |> load_rows()
       |> load_hero_row()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_hero_video_picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:hero_replacing_slide_id, nil)
     |> open_hero_picker()}
  end

  @impl true
  def handle_event("replace_hero_video", %{"slide-id" => slide_id}, socket) do
    {:noreply,
     socket
     |> assign(:hero_replacing_slide_id, slide_id)
     |> open_hero_picker()}
  end

  @impl true
  def handle_event("close_hero_video_picker", _params, socket) do
    if socket.assigns.hero_uploading do
      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         show_hero_video_picker: false,
         hero_available_videos: [],
         hero_picker_tab: :existing,
         hero_upload_file: nil,
         hero_replacing_slide_id: nil
       )}
    end
  end

  @impl true
  def handle_event("hero_picker_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :hero_picker_tab, String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("files_selected", %{"files" => [file | _]}, socket) do
    %{"client_id" => cid, "name" => name} = file
    title = name |> Path.rootname() |> String.replace(~r/[_\-\.]+/, " ") |> String.trim()
    {:noreply, assign(socket, :hero_upload_file, %{client_id: cid, name: name, title: title})}
  end

  @impl true
  def handle_event("submit_hero_upload", params, socket) do
    scope = socket.assigns.current_scope
    file = socket.assigns.hero_upload_file

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
           |> assign(
             hero_uploading: true,
             hero_upload_percent: 0,
             hero_pending_video_id: video.id
           )
           |> push_event("start_multi_upload", %{queue: queue})}

        {:error, :mux_error, reason} ->
          Logger.error("Hero upload initiation failed",
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

        {:error, :validation, _changeset} ->
          {:noreply, put_flash(socket, :error, "Invalid title for upload.")}
      end
    end
  end

  @impl true
  def handle_event("upload_progress", %{"percent" => pct}, socket) do
    {:noreply, assign(socket, :hero_upload_percent, pct)}
  end

  @impl true
  def handle_event("upload_complete", %{"video_id" => video_id}, socket) do
    replacing_id = socket.assigns.hero_replacing_slide_id
    result = finalize_hero_video(socket, video_id, replacing_id)

    case result do
      {:ok, message, socket} ->
        {:noreply,
         socket
         |> reset_hero_picker()
         |> put_flash(:info, message)
         |> load_hero_slides()}

      {:error, message, socket} ->
        {:noreply,
         socket
         |> reset_hero_picker()
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_event("upload_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(
       hero_uploading: false,
       hero_upload_percent: 0,
       hero_pending_video_id: nil,
       hero_upload_file: nil
     )
     |> put_flash(:error, "Upload failed: #{error}")}
  end

  @impl true
  def handle_event("add_hero_slide", %{"video-id" => video_id}, socket) do
    replacing_id = socket.assigns.hero_replacing_slide_id

    case finalize_hero_video(socket, video_id, replacing_id) do
      {:ok, _message, socket} ->
        {:noreply,
         socket
         |> reset_hero_picker()
         |> load_hero_slides()}

      {:error, message, socket} ->
        {:noreply,
         socket
         |> reset_hero_picker()
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_event("save_hero_slide", %{"slide-id" => slide_id} = params, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope
    autosave? = Map.has_key?(params, "_target")

    case Catalog.get_hero_slide(org, slide_id) do
      {:ok, slide} ->
        attrs = %{
          headline: blank_to_nil(params["headline"]),
          subheadline: blank_to_nil(params["subheadline"]),
          brand_tag: blank_to_nil(params["brand_tag"]),
          description: blank_to_nil(params["description"]),
          primary_cta_label: blank_to_nil(params["primary_cta_label"]),
          secondary_cta_label: blank_to_nil(params["secondary_cta_label"]),
          background_image_url: blank_to_nil(params["background_image_url"]),
          title_logo_url: blank_to_nil(params["title_logo_url"]),
          channel_logo_url: blank_to_nil(params["channel_logo_url"]),
          show_headline: checkbox_bool(params["show_headline"]),
          show_subheadline: checkbox_bool(params["show_subheadline"]),
          show_description: checkbox_bool(params["show_description"]),
          show_brand_tag: checkbox_bool(params["show_brand_tag"]),
          show_primary_cta: checkbox_bool(params["show_primary_cta"]),
          show_secondary_cta: checkbox_bool(params["show_secondary_cta"])
        }

        case Catalog.update_hero_slide(scope, slide, attrs) do
          {:ok, _} ->
            Process.send_after(self(), {:clear_hero_save_status, slide_id}, 3_000)

            socket =
              socket
              |> update(:hero_save_status, &Map.put(&1, slide_id, :ok))
              |> load_hero_slides()

            {:noreply,
             if(autosave?, do: socket, else: put_flash(socket, :info, "Slide updated."))}

          {:error, :validation, _changeset} ->
            Process.send_after(self(), {:clear_hero_save_status, slide_id}, 5_000)

            socket =
              socket
              |> update(:hero_save_status, &Map.put(&1, slide_id, :error))

            {:noreply,
             if(autosave?, do: socket, else: put_flash(socket, :error, "Failed to update slide."))}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Slide not found.")}
    end
  end

  @impl true
  def handle_event("remove_hero_slide", %{"slide-id" => slide_id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Catalog.get_hero_slide(org, slide_id) do
      {:ok, slide} ->
        {:ok, _} = Catalog.delete_hero_slide(scope, slide)
        {:noreply, load_hero_slides(socket)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Slide not found.")}
    end
  end

  @impl true
  def handle_event("move_hero_slide_up", %{"slide-id" => slide_id}, socket) do
    reorder_hero_slide(socket, slide_id, :up)
  end

  @impl true
  def handle_event("move_hero_slide_down", %{"slide-id" => slide_id}, socket) do
    reorder_hero_slide(socket, slide_id, :down)
  end

  @impl true
  def handle_event("save_hero_auto_advance", %{"auto_advance_ms" => ms_str}, socket) do
    scope = socket.assigns.current_scope
    hero_row = socket.assigns.hero_row

    if hero_row do
      ms = String.to_integer(ms_str)
      config = Map.merge(hero_row.filter_config || %{}, %{"auto_advance_ms" => ms})
      {:ok, _} = Catalog.update_row(scope, hero_row, %{filter_config: config})

      Process.send_after(self(), {:clear_hero_save_status, "auto_advance"}, 3_000)

      {:noreply,
       socket
       |> put_flash(:info, "Auto-rotate setting saved.")
       |> update(:hero_save_status, &Map.put(&1, "auto_advance", :ok))
       |> load_hero_row()}
    else
      {:noreply, socket}
    end
  end

  # ── Save status auto-clear ──────────────────────────────────────────────

  @impl true
  def handle_info({:clear_hero_save_status, key}, socket) do
    {:noreply, update(socket, :hero_save_status, &Map.delete(&1, key))}
  end

  # ── PubSub ─────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    {:noreply, load_rows(socket)}
  end

  # ── Data loading ───────────────────────────────────────────────────────

  defp load_rows(socket) do
    org = socket.assigns.organization
    %{results: rows} = Catalog.list_rows(org)
    # Filter hero rows from the regular rows list — hero is managed separately
    non_hero_rows = Enum.reject(rows, &(&1.source_type == :hero))
    assign(socket, :rows, non_hero_rows)
  end

  defp load_hero_row(socket) do
    org = socket.assigns.organization

    case Catalog.get_hero_row(org) do
      {:ok, row} ->
        socket
        |> assign(:hero_row, row)
        |> load_hero_slides()

      {:error, :not_found} ->
        assign(socket, hero_row: nil, hero_slides: [])
    end
  end

  defp load_hero_slides(socket) do
    org = socket.assigns.organization
    hero_row = socket.assigns.hero_row

    if hero_row do
      enriched = Catalog.list_enriched_hero_slides(org, hero_row)
      expanded = socket.assigns.hero_expanded_slide

      expanded =
        cond do
          expanded && Enum.any?(enriched, &(&1.id == expanded)) -> expanded
          enriched != [] -> hd(enriched).id
          true -> nil
        end

      socket
      |> assign(:hero_slides, enriched)
      |> assign(:hero_expanded_slide, expanded)
    else
      assign(socket, hero_slides: [], hero_expanded_slide: nil)
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp reorder_row(socket, id, direction) do
    rows = socket.assigns.rows
    index = Enum.find_index(rows, &(&1.id == id))

    new_index =
      case direction do
        :up -> max(0, index - 1)
        :down -> min(length(rows) - 1, index + 1)
      end

    if index != new_index do
      scope = socket.assigns.current_scope
      reordered = swap(rows, index, new_index)
      ordered_ids = Enum.map(reordered, & &1.id)
      :ok = Catalog.reorder_rows(scope, ordered_ids)
      {:noreply, load_rows(socket)}
    else
      {:noreply, socket}
    end
  end

  defp reorder_hero_slide(socket, slide_id, direction) do
    slides = socket.assigns.hero_slides
    index = Enum.find_index(slides, &(&1.id == slide_id))

    new_index =
      case direction do
        :up -> max(0, index - 1)
        :down -> min(length(slides) - 1, index + 1)
      end

    if index != new_index do
      scope = socket.assigns.current_scope
      hero_row = socket.assigns.hero_row
      reordered = swap(slides, index, new_index)
      ordered_ids = Enum.map(reordered, & &1.id)
      :ok = Catalog.reorder_hero_slides(scope, hero_row, ordered_ids)
      {:noreply, load_hero_slides(socket)}
    else
      {:noreply, socket}
    end
  end

  defp swap(list, i, j) do
    list
    |> List.replace_at(i, Enum.at(list, j))
    |> List.replace_at(j, Enum.at(list, i))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(str) when is_binary(str), do: str

  # HTML checkbox convention: hidden "false" input before the checkbox means
  # params carry "false" when unchecked and "true" when checked. Any other
  # value (missing key, unexpected) defaults to visible.
  defp checkbox_bool("false"), do: false
  defp checkbox_bool(false), do: false
  defp checkbox_bool("true"), do: true
  defp checkbox_bool(true), do: true
  defp checkbox_bool(_), do: true

  defp normalize_variant(""), do: nil
  defp normalize_variant(nil), do: nil
  defp normalize_variant(variant) when is_binary(variant), do: variant

  defp format_changeset_errors(changeset) do
    Enum.map_join(changeset.errors, "; ", fn {f, {m, _}} -> "#{f}: #{m}" end)
  end

  defp open_hero_picker(socket) do
    org = socket.assigns.organization
    %{results: all_videos} = Content.list_videos(org, per_page: 100)
    hero_video_ids = MapSet.new(socket.assigns.hero_slides, & &1.video_id)
    available = Enum.reject(all_videos, &MapSet.member?(hero_video_ids, &1.id))

    assign(socket, show_hero_video_picker: true, hero_available_videos: available)
  end

  defp reset_hero_picker(socket) do
    assign(socket,
      show_hero_video_picker: false,
      hero_available_videos: [],
      hero_picker_tab: :existing,
      hero_upload_file: nil,
      hero_uploading: false,
      hero_upload_percent: 0,
      hero_pending_video_id: nil,
      hero_replacing_slide_id: nil
    )
  end

  # Shared finalizer: new slide if `replacing_id` nil, otherwise update
  # the target slide's video_id. Returns {:ok, flash_message, socket} or
  # {:error, flash_message, socket}.
  defp finalize_hero_video(socket, video_id, nil) do
    scope = socket.assigns.current_scope
    hero_row = socket.assigns.hero_row

    case Catalog.create_hero_slide(scope, hero_row, %{video_id: video_id}) do
      {:ok, slide} ->
        {:ok, "Slide added. Processing video…", assign(socket, :hero_expanded_slide, slide.id)}

      {:error, :hero_limit_reached, _} ->
        {:error, "Maximum of 4 hero slides reached.", socket}

      {:error, :validation, _changeset} ->
        {:error, "Failed to add hero slide.", socket}
    end
  end

  defp finalize_hero_video(socket, video_id, slide_id) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    with {:ok, slide} <- Catalog.get_hero_slide(org, slide_id),
         {:ok, _} <- Catalog.update_hero_slide(scope, slide, %{video_id: video_id}) do
      {:ok, "Video replaced. Processing…", assign(socket, :hero_expanded_slide, slide_id)}
    else
      {:error, :not_found} -> {:error, "Slide not found.", socket}
      {:error, :validation, _} -> {:error, "Failed to replace video.", socket}
    end
  end
end
