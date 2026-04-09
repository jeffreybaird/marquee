defmodule BobineWeb.Admin.LandingLive do
  @moduledoc """
  Admin editor for the configurable marketing landing page.

  Operators can add, edit, reorder, hide, and delete landing sections.
  Each section type has its own config form. On first visit, if the org has
  no sections, a default starter page is seeded.

  Events: add_section, edit_section, cancel_edit, save_section, delete_section,
  toggle_visibility, move_up, move_down, faq_add_item, faq_remove_item
  Route: /admin/landing
  """

  use BobineWeb, :live_view

  alias Bobine.Accounts
  alias Bobine.Content
  alias Bobine.LandingPage
  alias Bobine.LandingPage.LandingSection

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

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add section.")}
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

  ## --- helpers ----------------------------------------------------------

  defp load_sections(socket) do
    org = socket.assigns.organization
    sections = LandingPage.list_landing_sections_admin(org)
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

    %{config: config, visible: visible_param(params)}
  end

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
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <.header>
        Landing Page
        <:subtitle>Build the page visitors see before they sign up.</:subtitle>
      </.header>

      <div class="admin-landing-editor mt-6" data-test="landing-editor">
        <div class="admin-section-list space-y-2" data-test="section-list">
          <div
            :for={{section, index} <- Enum.with_index(@sections)}
            class={[
              "admin-section-item flex items-center gap-3 rounded-lg border border-base-300 bg-base-200 p-3",
              !section.visible && "opacity-60"
            ]}
            data-id={section.id}
            data-test={"section-item-#{section.id}"}
          >
            <div class="flex flex-col">
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="move_up"
                phx-value-id={section.id}
                disabled={index == 0}
                aria-label="Move section up"
              >
                ▲
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
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
              <div class="text-sm text-base-content/70">{section_preview_text(section)}</div>
            </div>

            <div class="admin-section-actions flex gap-2">
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="toggle_visibility"
                phx-value-id={section.id}
                data-test={"toggle-visibility-#{section.id}"}
              >
                {if section.visible, do: "Hide", else: "Show"}
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="edit_section"
                phx-value-id={section.id}
                data-test={"edit-section-#{section.id}"}
              >
                Edit
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm text-error"
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
            class="rounded-lg border border-dashed border-base-300 p-6 text-center text-base-content/70"
            data-test="empty-state"
          >
            No landing sections yet. Add one below.
          </div>
        </div>

        <div class="admin-add-section mt-4" data-test="add-section">
          <form phx-change="add_section" id="add-section-form">
            <select name="section_type" class="select select-bordered" data-test="add-section-select">
              <option value="">+ Add section…</option>
              <option :for={{label, value} <- @section_type_options} value={value}>{label}</option>
            </select>
          </form>
        </div>

        <div
          :if={@editing_section}
          class="mt-6 rounded-lg border border-base-300 bg-base-100 p-4"
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
    </BobineWeb.Components.AdminLayout.admin_layout>
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
      <.text_input name="subheadline" label="Subheadline" value={@form["subheadline"]} />
      <.text_input name="video_url" label="Video URL (.mp4)" value={@form["video_url"]} />
      <.text_input
        name="video_playback_id"
        label="Or Mux playback ID"
        value={@form["video_playback_id"]}
      />
      <.text_input
        name="fallback_image_url"
        label="Fallback image URL"
        value={@form["fallback_image_url"]}
      />
      <.text_input name="cta_text" label="CTA text" value={@form["cta_text"]} />
      <.text_input name="cta_link" label="CTA link" value={@form["cta_link"]} />
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
      <.text_input name="subheadline" label="Subheadline" value={@form["subheadline"]} />
      <.text_input name="image_url" label="Image URL" value={@form["image_url"]} />
      <.text_input name="cta_text" label="CTA text" value={@form["cta_text"]} />
      <.text_input name="cta_link" label="CTA link" value={@form["cta_link"]} />
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
          class="textarea textarea-bordered w-full"
        >{@form["body"]}</textarea>
      </label>
      <.text_input name="cta_text" label="CTA text" value={@form["cta_text"]} />
      <.text_input name="cta_link" label="CTA link" value={@form["cta_link"]} />
      <label class="block">
        <span class="block text-sm font-medium mb-1">Text alignment</span>
        <select name="text_alignment" class="select select-bordered w-full">
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
        <select name="source_type" class="select select-bordered w-full">
          <option value="recent" selected={@form["source_type"] == "recent"}>Recent videos</option>
          <option value="collection" selected={@form["source_type"] == "collection"}>
            Collection
          </option>
        </select>
      </label>
      <label class="block">
        <span class="block text-sm font-medium mb-1">Collection (when source = collection)</span>
        <select name="source_id" class="select select-bordered w-full">
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
      <p class="text-sm text-base-content/70">
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
        <select name="size" class="select select-bordered w-full">
          <option value="small" selected={@form["size"] == "small"}>Small</option>
          <option value="medium" selected={@form["size"] == "medium"}>Medium</option>
          <option value="large" selected={@form["size"] == "large"}>Large</option>
        </select>
      </label>
      <label class="block">
        <span class="block text-sm font-medium mb-1">Alignment</span>
        <select name="text_alignment" class="select select-bordered w-full">
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
          class="rounded border border-base-300 p-2"
          data-test={"faq-edit-item-#{index}"}
        >
          <input
            type="text"
            name={"faq[#{index}][question]"}
            value={item["question"]}
            placeholder="Question"
            class="input input-bordered w-full mb-1"
          />
          <textarea
            name={"faq[#{index}][answer]"}
            rows="2"
            placeholder="Answer"
            class="textarea textarea-bordered w-full"
          >{item["answer"]}</textarea>
          <button
            type="button"
            class="btn btn-ghost btn-xs mt-1"
            phx-click="faq_remove_item"
            phx-value-index={index}
          >
            Remove
          </button>
        </div>
      </div>

      <button type="button" class="btn btn-sm" phx-click="faq_add_item">+ Add item</button>
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
      <input type="text" name={@name} value={@value} class="input input-bordered w-full" />
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
        class="input input-bordered w-full"
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

  defp form_buttons(assigns) do
    ~H"""
    <div class="flex gap-2 mt-3">
      <button type="submit" class="btn btn-primary btn-sm" data-test="save-section">Save</button>
      <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
    </div>
    """
  end
end
