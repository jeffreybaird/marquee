defmodule MarqueeWeb.Admin.ShortsLive do
  @moduledoc """
  Shorts feed management. Operators switch the vertical feed on or off,
  choose who can watch it, and add, reorder and remove eligible videos.

  Editors and above (or super admins) manage the feed; viewer support sees
  it read-only. Controls are hidden for read-only roles, and the context
  enforces the role for every mutation, so forced events are refused.

  Events: toggle_enabled, set_access, open_picker, close_picker,
  search_picker, add_video, remove_item, move_item, items_page
  Route: /admin/shorts
  """

  use MarqueeWeb, :live_view

  alias Marquee.Accounts
  alias Marquee.Accounts.{Organization, Scope}
  alias Marquee.Content
  alias Marquee.Content.AspectRatio
  alias Marquee.Events
  alias MarqueeWeb.Components.AdminUI

  import MarqueeWeb.Viewer.WatchLive.Components, only: [format_duration: 1]

  @items_per_page 100
  @picker_per_page 50

  # Copy for each level; the levels themselves come from the schema so the
  # form can never offer a value the changeset rejects.
  @access_copy %{
    "public" => {"Everyone", "Anyone can watch, signed in or not."},
    "free_with_account" => {"Free with an account", "Any signed-in viewer can watch."},
    "subscribers_only" => {"Subscribers only", "Only viewers with an active subscription."}
  }

  @access_options Enum.map(Organization.shorts_feed_access_levels(), fn level ->
                    {label, help} = Map.get(@access_copy, level, {level, ""})
                    {level, label, help}
                  end)

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization

    if connected?(socket), do: Events.subscribe(org.id)

    {:ok,
     socket
     |> assign(:page_title, "Shorts")
     |> assign(:can_manage, Accounts.can_manage_content?(socket.assigns.current_scope))
     |> assign(:access_options, @access_options)
     |> assign(:items_page, 1)
     |> assign(:picker_open, false)
     |> assign(:picker_search, "")
     |> assign(:picker_videos, [])
     |> load_items()}
  end

  ## -----------------------------------------------------------------------
  ## Settings
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("toggle_enabled", _params, socket) do
    org = socket.assigns.organization

    save_settings(socket, %{
      enabled: !org.shorts_feed_enabled,
      access: org.shorts_feed_access
    })
  end

  def handle_event("set_access", %{"access" => access}, socket) do
    save_settings(socket, %{
      enabled: socket.assigns.organization.shorts_feed_enabled,
      access: access
    })
  end

  ## -----------------------------------------------------------------------
  ## Picker
  ## -----------------------------------------------------------------------

  def handle_event("open_picker", _params, socket) do
    if socket.assigns.can_manage do
      {:noreply, socket |> assign(:picker_open, true) |> load_picker()}
    else
      {:noreply, refuse(socket)}
    end
  end

  def handle_event("close_picker", _params, socket) do
    {:noreply, assign(socket, picker_open: false, picker_videos: [], picker_search: "")}
  end

  def handle_event("search_picker", %{"search" => search}, socket) do
    if socket.assigns.picker_open do
      {:noreply, socket |> assign(:picker_search, search) |> load_picker()}
    else
      {:noreply, socket}
    end
  end

  ## -----------------------------------------------------------------------
  ## Items
  ## -----------------------------------------------------------------------

  def handle_event("add_video", %{"video-id" => video_id}, socket) do
    with {:ok, video} <- fetch_video(socket.assigns.organization, video_id),
         {:ok, _item} <- Content.add_short_feed_video(socket.assigns.current_scope, video) do
      {:noreply,
       socket
       |> put_flash(:info, "Added to Shorts.")
       |> load_items()
       |> refresh_picker()}
    else
      error -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    with {:ok, item} <- Content.get_short_feed_item(socket.assigns.organization, id),
         :ok <- Content.remove_short_feed_item(socket.assigns.current_scope, item) do
      {:noreply,
       socket
       |> put_flash(:info, "Removed from Shorts.")
       |> load_items()
       |> refresh_picker()}
    else
      error -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("move_item", %{"id" => id, "direction" => direction}, socket)
      when direction in ["up", "down"] do
    with {:ok, item} <- Content.get_short_feed_item(socket.assigns.organization, id),
         :ok <-
           Content.move_short_feed_item(
             socket.assigns.current_scope,
             item,
             String.to_existing_atom(direction)
           ) do
      {:noreply, load_items(socket)}
    else
      error -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("move_item", _params, socket) do
    {:noreply, put_flash(socket, :error, "That move isn't supported.")}
  end

  def handle_event("items_page", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {page, ""} when page >= 1 -> {:noreply, socket |> assign(:items_page, page) |> load_items()}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:marquee_event, {name, _resource}, _scope}, socket) when is_atom(name) do
    if refresh_event?(name),
      do: {:noreply, load_items(socket)},
      else: {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh_event?(name) do
    name_string = Atom.to_string(name)
    String.starts_with?(name_string, "short_feed_") or String.starts_with?(name_string, "video_")
  end

  ## -----------------------------------------------------------------------
  ## Helpers
  ## -----------------------------------------------------------------------

  defp save_settings(socket, attrs) do
    case Content.update_short_feed_settings(socket.assigns.current_scope, attrs) do
      {:ok, %Organization{} = org} ->
        {:noreply,
         socket
         |> assign(:organization, org)
         |> assign(:current_scope, put_scope_org(socket.assigns.current_scope, org))
         |> put_flash(:info, "Shorts settings saved.")}

      error ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  defp put_scope_org(%Scope{} = scope, org), do: %{scope | organization: org}
  defp put_scope_org(scope, _org), do: scope

  defp fetch_video(org, video_id) do
    case Content.get_video(org, video_id) do
      {:ok, video} -> {:ok, video}
      _ -> {:error, :not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp load_items(socket) do
    page =
      Content.list_short_feed_items(socket.assigns.organization,
        page: socket.assigns.items_page,
        per_page: @items_per_page
      )

    socket
    |> assign(:items, page.results)
    |> assign(:items_total, page.total)
    |> assign(:items_total_pages, page.total_pages)
    |> assign(:items_offset, (page.page - 1) * page.per_page)
  end

  defp load_picker(socket) do
    %{results: videos} =
      Content.list_short_feed_eligible_videos(socket.assigns.organization,
        search: socket.assigns.picker_search,
        per_page: @picker_per_page
      )

    assign(socket, :picker_videos, videos)
  end

  defp refresh_picker(%{assigns: %{picker_open: true}} = socket), do: load_picker(socket)
  defp refresh_picker(socket), do: socket

  defp refuse(socket),
    do: put_flash(socket, :error, "You don't have permission to manage Shorts.")

  defp error_message({:error, :forbidden}), do: "You don't have permission to manage Shorts."
  defp error_message({:error, :demo_forbidden}), do: "This action isn't available in the demo."
  defp error_message({:error, :not_found}), do: "That item could not be found."

  defp error_message({:error, :not_eligible}),
    do: "That video isn't ready to play, so it can't be added."

  defp error_message({:error, :already_exists}), do: "That video is already in Shorts."

  defp error_message({:error, :plan_limit_reached, %{limit: limit}}),
    do: "Shorts can hold up to #{limit} videos. Remove one to add another."

  defp error_message({:error, :validation, _changeset}), do: "Those settings aren't valid."
  defp error_message(_error), do: "Something went wrong. Please try again."

  defp item_available?(%{video: video}) do
    video.deleted_at == nil and video.mux_status == "ready" and
      is_binary(video.mux_playback_id) and video.mux_playback_id != ""
  end

  defp orientation_label(aspect_ratio) do
    case AspectRatio.orientation(aspect_ratio) do
      :portrait -> "Portrait"
      :landscape -> "Landscape"
      :square -> "Square"
      :unknown -> "Unknown ratio"
    end
  end

  ## -----------------------------------------------------------------------
  ## Render
  ## -----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      trial_status={@trial_status}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
      flash={@flash}
    >
      <AdminUI.admin_panel
        title="Shorts"
        subtitle="A vertical feed of short clips for your viewers at /shorts."
      >
        <:actions :if={@can_manage}>
          <button
            type="button"
            phx-click="open_picker"
            data-test="shorts-open-picker"
            class={button_class(:accent)}
          >
            <.icon name="hero-plus" class="size-4" /> Add videos
          </button>
        </:actions>

        <div class="space-y-6">
          <AdminUI.admin_section title="Feed settings" data_test="shorts-settings">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div>
                <p id="shorts-enabled-label" class="font-ui text-sm font-medium text-admin-fg">
                  Show Shorts to viewers
                </p>
                <p id="shorts-enabled-help" class="text-sm text-admin-muted">
                  Adds Shorts to your site navigation.
                </p>
              </div>
              <button
                :if={@can_manage}
                type="button"
                role="switch"
                aria-checked={to_string(@organization.shorts_feed_enabled)}
                aria-labelledby="shorts-enabled-label"
                aria-describedby="shorts-enabled-help"
                phx-click="toggle_enabled"
                data-test="shorts-enabled-toggle"
                class={[
                  "relative inline-flex h-11 w-20 shrink-0 items-center rounded-full border-2 transition-colors",
                  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent",
                  if(@organization.shorts_feed_enabled,
                    do: "border-admin-accent bg-admin-accent",
                    else: "border-admin-border bg-admin-bg"
                  )
                ]}
              >
                <span class="sr-only">
                  {if @organization.shorts_feed_enabled, do: "On", else: "Off"}
                </span>
                <span
                  aria-hidden="true"
                  class={[
                    "inline-block size-8 rounded-full bg-white shadow transition-transform",
                    if(@organization.shorts_feed_enabled, do: "translate-x-9", else: "translate-x-1")
                  ]}
                />
              </button>
              <p
                :if={!@can_manage}
                class="font-ui text-sm text-admin-fg"
                data-test="shorts-enabled-status"
              >
                {if @organization.shorts_feed_enabled, do: "On", else: "Off"}
              </p>
            </div>

            <form
              :if={@can_manage}
              id="shorts-access-form"
              phx-change="set_access"
              data-test="shorts-access-form"
            >
              <fieldset data-test="shorts-access-select" class="space-y-2">
                <legend class="font-ui text-sm font-medium text-admin-fg">Who can watch</legend>
                <div :for={{value, label, help} <- @access_options} class="flex items-start gap-3">
                  <input
                    type="radio"
                    id={"shorts-access-#{value}"}
                    name="access"
                    value={value}
                    checked={@organization.shorts_feed_access == value}
                    aria-describedby={"shorts-access-#{value}-help"}
                    class="mt-1 size-5 accent-admin-accent focus-visible:outline-2 focus-visible:outline-admin-accent"
                  />
                  <label for={"shorts-access-#{value}"} class="text-sm">
                    <span class="font-medium text-admin-fg">{label}</span>
                    <span id={"shorts-access-#{value}-help"} class="block text-admin-muted">
                      {help}
                    </span>
                  </label>
                </div>
              </fieldset>
            </form>
            <p :if={!@can_manage} class="text-sm text-admin-muted" data-test="shorts-access-status">
              Who can watch: {access_label(@access_options, @organization.shorts_feed_access)}
            </p>
          </AdminUI.admin_section>

          <AdminUI.admin_empty
            :if={@items_total == 0}
            title="No Shorts yet"
            description="Add ready videos to build your vertical feed."
            data_test="shorts-admin-empty"
          />

          <ol
            :if={@items != []}
            class="space-y-2"
            data-test="shorts-items"
            aria-label="Shorts feed order"
          >
            <li
              :for={{item, index} <- Enum.with_index(@items, @items_offset)}
              data-test={"shorts-item-#{item.id}"}
              class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-admin-border bg-admin-card p-3"
            >
              <div class="flex min-w-0 items-center gap-3">
                <span class="w-8 shrink-0 text-right font-mono text-xs text-admin-muted">
                  {index + 1}
                </span>
                <div class="min-w-0">
                  <p class="truncate font-ui text-sm font-medium text-admin-fg">{item.video.title}</p>
                  <p class="flex flex-wrap items-center gap-2 text-xs text-admin-muted">
                    <span data-test={"shorts-item-orientation-#{item.id}"}>
                      {orientation_label(item.video.aspect_ratio)}
                    </span>
                    <span :if={item.video.duration}>{format_duration(item.video.duration)}</span>
                    <span
                      data-test={"shorts-item-status-#{item.id}"}
                      class={[
                        "rounded-full border px-2 py-0.5 font-medium",
                        if(item_available?(item),
                          do: "border-admin-border text-admin-fg",
                          else: "border-error text-error"
                        )
                      ]}
                    >
                      {if item_available?(item), do: "Ready", else: "Unavailable"}
                    </span>
                  </p>
                </div>
              </div>

              <div :if={@can_manage} class="flex items-center gap-1">
                <button
                  type="button"
                  phx-click="move_item"
                  phx-value-id={item.id}
                  phx-value-direction="up"
                  data-test={"shorts-move-up-#{item.id}"}
                  aria-label={"Move #{item.video.title} up"}
                  class={icon_button_class()}
                >
                  <.icon name="hero-arrow-up" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="move_item"
                  phx-value-id={item.id}
                  phx-value-direction="down"
                  data-test={"shorts-move-down-#{item.id}"}
                  aria-label={"Move #{item.video.title} down"}
                  class={icon_button_class()}
                >
                  <.icon name="hero-arrow-down" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="remove_item"
                  phx-value-id={item.id}
                  data-test={"shorts-remove-#{item.id}"}
                  aria-label={"Remove #{item.video.title} from Shorts"}
                  class={icon_button_class()}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </li>
          </ol>

          <nav
            :if={@items_total_pages > 1}
            aria-label="Shorts pages"
            class="flex items-center justify-between"
          >
            <button
              type="button"
              phx-click="items_page"
              phx-value-page={@items_page - 1}
              disabled={@items_page <= 1}
              class={button_class(:secondary)}
            >
              Previous page
            </button>
            <span class="text-sm text-admin-muted">
              Page {@items_page} of {@items_total_pages}
            </span>
            <button
              type="button"
              phx-click="items_page"
              phx-value-page={@items_page + 1}
              disabled={@items_page >= @items_total_pages}
              class={button_class(:secondary)}
            >
              Next page
            </button>
          </nav>
        </div>
      </AdminUI.admin_panel>

      <AdminUI.admin_sheet
        id="shorts-picker"
        open={@picker_open and @can_manage}
        title="Add videos to Shorts"
        subtitle="Only videos that are ready to play can be added."
        on_close="close_picker"
        data_test="shorts-picker"
      >
        <form
          id="shorts-picker-search"
          phx-change="search_picker"
          phx-submit="search_picker"
          data-test="shorts-picker-search"
          class="mb-4"
        >
          <label for="shorts-picker-search-input" class="mb-1 block text-sm font-medium">
            Search videos
          </label>
          <input
            type="search"
            id="shorts-picker-search-input"
            name="search"
            value={@picker_search}
            phx-debounce="300"
            autocomplete="off"
            class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 text-sm text-admin-fg focus:border-admin-accent focus:outline-none focus-visible:outline-2 focus-visible:outline-admin-accent"
          />
        </form>

        <p :if={@picker_videos == []} class="text-sm text-admin-muted" data-test="shorts-picker-empty">
          No eligible videos found.
        </p>

        <ul :if={@picker_videos != []} class="space-y-2">
          <li
            :for={video <- @picker_videos}
            data-test={"shorts-picker-video-#{video.id}"}
            class="flex items-center justify-between gap-3 rounded-md border border-admin-border p-3"
          >
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-admin-fg">{video.title}</p>
              <p class="text-xs text-admin-muted">
                {orientation_label(video.aspect_ratio)}
                <span :if={video.duration}>· {format_duration(video.duration)}</span>
              </p>
            </div>
            <button
              type="button"
              phx-click="add_video"
              phx-value-video-id={video.id}
              data-test={"shorts-add-#{video.id}"}
              aria-label={"Add #{video.title} to Shorts"}
              class={button_class(:accent)}
            >
              Add
            </button>
          </li>
        </ul>
      </AdminUI.admin_sheet>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp access_label(options, value) do
    Enum.find_value(options, value, fn {option, label, _help} -> option == value && label end)
  end

  defp button_class(:accent) do
    "inline-flex min-h-11 items-center justify-center gap-1.5 rounded-md bg-admin-accent px-4 py-2 " <>
      "font-ui text-sm font-medium text-admin-on-accent transition-colors hover:brightness-110 " <>
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent"
  end

  defp button_class(:secondary) do
    "inline-flex min-h-11 items-center justify-center rounded-md border border-admin-border bg-admin-card px-4 py-2 " <>
      "font-ui text-sm font-medium text-admin-fg disabled:cursor-not-allowed disabled:opacity-50 " <>
      "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-admin-accent"
  end

  defp icon_button_class do
    "inline-flex size-11 items-center justify-center rounded-md text-admin-muted transition-colors " <>
      "hover:bg-admin-bg hover:text-admin-fg focus-visible:outline-2 focus-visible:outline-offset-2 " <>
      "focus-visible:outline-admin-accent"
  end
end
