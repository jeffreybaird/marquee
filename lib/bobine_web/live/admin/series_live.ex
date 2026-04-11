defmodule BobineWeb.Admin.SeriesLive do
  @moduledoc """
  Series and season management.

  List view shows all series for the current org with create/edit/delete.
  Selecting a series switches to the detail view, which lists its seasons
  and supports create/edit/delete of seasons under that series.

  Events: new_series, edit_series, save_series, delete_series, view_series,
          back_to_list, new_season, edit_season, save_season, delete_season
  Route: /admin/series
  """

  use BobineWeb, :live_view
  use BobineWeb.Admin.ImageUploadHandlers

  alias Bobine.Accounts
  alias Bobine.Content
  alias Bobine.Content.{Season, Series}
  alias Bobine.Events
  alias BobineWeb.Admin.ImageUploadHandlers

  @upload_kinds ~w(series_cover season_cover)

  @impl true
  def allowed_upload_kind?(kind), do: kind in @upload_kinds

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
     |> assign(:page_title, "Series")
     |> assign(:can_manage, can_manage)
     |> assign(:show_series_form, false)
     |> assign(:editing_series, nil)
     |> assign(:series_form, nil)
     |> assign(:selected_series, nil)
     |> assign(:seasons, [])
     |> assign(:show_season_form, false)
     |> assign(:editing_season, nil)
     |> assign(:season_form, nil)
     |> load_series()}
  end

  ## -----------------------------------------------------------------------
  ## Series CRUD
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("new_series", _params, socket) do
    form = Content.change_series(%Series{}) |> to_form()

    socket =
      socket
      |> ImageUploadHandlers.put_initial_url("series_cover", series_cover_target(nil), nil)
      |> assign(show_series_form: true, editing_series: nil, series_form: form)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_series", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_series(org, id) do
      {:ok, series} ->
        form = Content.change_series(series) |> to_form()

        socket =
          socket
          |> ImageUploadHandlers.put_initial_url(
            "series_cover",
            series_cover_target(series),
            series.cover_image_url
          )
          |> assign(show_series_form: true, editing_series: series, series_form: form)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Series not found.")}
    end
  end

  @impl true
  def handle_event("cancel_series_form", _params, socket) do
    {:noreply, assign(socket, show_series_form: false, editing_series: nil, series_form: nil)}
  end

  @impl true
  def handle_event("save_series", %{"series" => params}, socket) do
    scope = socket.assigns.current_scope

    target_id = series_cover_target(socket.assigns.editing_series)
    uploaded_url = ImageUploadHandlers.upload_url(socket, "series_cover", target_id)

    params =
      params
      |> normalize_new_season_params()
      |> maybe_put_cover_image_url(uploaded_url)

    result =
      case socket.assigns.editing_series do
        nil -> Content.create_series(scope, params)
        series -> Content.update_series(scope, series, params)
      end

    case result do
      {:ok, _series} ->
        {:noreply,
         socket
         |> assign(show_series_form: false, editing_series: nil, series_form: nil)
         |> put_flash(:info, "Series saved.")
         |> load_series()}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, series_form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_series", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_series(org, id) do
      {:ok, series} ->
        {:ok, _} = Content.delete_series(scope, series)

        {:noreply,
         socket
         |> put_flash(:info, "Series deleted.")
         |> load_series()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Series not found.")}
    end
  end

  @impl true
  def handle_event("toggle_series_visibility", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_series(org, id) do
      {:ok, series} ->
        {:ok, _} = Content.update_series(scope, series, %{visible: !series.visible})
        {:noreply, load_series(socket)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("view_series", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_series(org, id) do
      {:ok, series} ->
        {:noreply,
         socket
         |> assign(selected_series: series)
         |> load_seasons()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Series not found.")}
    end
  end

  @impl true
  def handle_event("back_to_series_list", _params, socket) do
    {:noreply,
     assign(socket,
       selected_series: nil,
       seasons: [],
       show_season_form: false,
       editing_season: nil,
       season_form: nil
     )}
  end

  ## -----------------------------------------------------------------------
  ## Season CRUD
  ## -----------------------------------------------------------------------

  @impl true
  def handle_event("new_season", _params, socket) do
    form = Content.change_season(%Season{}) |> to_form()

    socket =
      socket
      |> ImageUploadHandlers.put_initial_url("season_cover", season_cover_target(nil), nil)
      |> assign(show_season_form: true, editing_season: nil, season_form: form)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_season", %{"id" => id}, socket) do
    org = socket.assigns.organization

    case Content.get_season(org, id) do
      {:ok, season} ->
        form = Content.change_season(season) |> to_form()

        socket =
          socket
          |> ImageUploadHandlers.put_initial_url(
            "season_cover",
            season_cover_target(season),
            season.cover_image_url
          )
          |> assign(show_season_form: true, editing_season: season, season_form: form)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Season not found.")}
    end
  end

  @impl true
  def handle_event("cancel_season_form", _params, socket) do
    {:noreply, assign(socket, show_season_form: false, editing_season: nil, season_form: nil)}
  end

  @impl true
  def handle_event("save_season", %{"season" => params}, socket) do
    scope = socket.assigns.current_scope
    series = socket.assigns.selected_series

    target_id = season_cover_target(socket.assigns.editing_season)
    uploaded_url = ImageUploadHandlers.upload_url(socket, "season_cover", target_id)

    params =
      params
      |> drop_blank_season_number()
      |> maybe_put_cover_image_url(uploaded_url)

    result =
      case socket.assigns.editing_season do
        nil ->
          Content.create_season(scope, series, drop_blank_title(params))

        season ->
          Content.update_season(scope, season, params)
      end

    case result do
      {:ok, _season} ->
        {:noreply,
         socket
         |> assign(show_season_form: false, editing_season: nil, season_form: nil)
         |> put_flash(:info, "Season saved.")
         |> load_seasons()}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, season_form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_season", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_season(org, id) do
      {:ok, season} ->
        {:ok, _} = Content.delete_season(scope, season)

        {:noreply,
         socket
         |> put_flash(:info, "Season deleted.")
         |> load_seasons()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Season not found.")}
    end
  end

  @impl true
  def handle_event("toggle_season_visibility", %{"id" => id}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    case Content.get_season(org, id) do
      {:ok, season} ->
        {:ok, _} = Content.update_season(scope, season, %{visible: !season.visible})
        {:noreply, load_seasons(socket)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  ## -----------------------------------------------------------------------
  ## Real-time updates
  ## -----------------------------------------------------------------------

  @impl true
  def handle_info({:bobine_event, _event, _scope}, socket) do
    socket = load_series(socket)

    socket =
      if socket.assigns.selected_series do
        load_seasons(socket)
      else
        socket
      end

    {:noreply, socket}
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
      <%= if @selected_series do %>
        <.series_detail_view
          series={@selected_series}
          seasons={@seasons}
          can_manage={@can_manage}
          show_season_form={@show_season_form}
          season_form={@season_form}
          editing_season={@editing_season}
          season_cover_target={season_cover_target(@editing_season)}
          season_cover_state={
            ImageUploadHandlers.upload_state(
              @image_uploads,
              "season_cover",
              season_cover_target(@editing_season)
            )
          }
        />
      <% else %>
        <.series_list_view
          series_list={@series_list}
          can_manage={@can_manage}
          show_series_form={@show_series_form}
          series_form={@series_form}
          editing_series={@editing_series}
          series_cover_target={series_cover_target(@editing_series)}
          series_cover_state={
            ImageUploadHandlers.upload_state(
              @image_uploads,
              "series_cover",
              series_cover_target(@editing_series)
            )
          }
        />
      <% end %>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp series_list_view(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-4">
      <.header>Series</.header>
      <button
        :if={@can_manage}
        phx-click="new_series"
        class="btn btn-primary"
        data-test="new-series-btn"
      >
        New Series
      </button>
    </div>

    <div
      :if={@series_list == []}
      class="py-12 text-center text-base-content/60"
      data-test="empty-state"
    >
      <p class="text-lg">No series yet.</p>
      <p class="mt-2">Create your first series to organize seasons and episodes.</p>
    </div>

    <div :if={@series_list != []} data-test="series-list" class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr>
            <th>Title</th>
            <th>Visible</th>
            <th>New Season</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={series <- @series_list} data-test={"series-row-#{series.id}"}>
            <td>
              <button
                phx-click="view_series"
                phx-value-id={series.id}
                class="font-medium hover:text-primary hover:underline"
                data-test={"view-series-#{series.id}"}
              >
                {series.title}
              </button>
              <div class="text-xs text-base-content/60 font-mono">{series.slug}</div>
            </td>
            <td>
              <button
                :if={@can_manage}
                phx-click="toggle_series_visibility"
                phx-value-id={series.id}
                data-test={"series-visibility-#{series.id}"}
                class={"badge badge-sm #{if series.visible, do: "badge-success", else: "badge-ghost"}"}
              >
                {if series.visible, do: "Visible", else: "Hidden"}
              </button>
              <span :if={!@can_manage} class="badge badge-sm badge-ghost">
                {if series.visible, do: "Visible", else: "Hidden"}
              </span>
            </td>
            <td data-test={"series-new-season-status-#{series.id}"}>
              <.new_season_status series={series} />
            </td>
            <td :if={@can_manage}>
              <div class="flex gap-1">
                <button
                  phx-click="edit_series"
                  phx-value-id={series.id}
                  class="btn btn-xs btn-outline"
                  data-test={"edit-series-#{series.id}"}
                >
                  Edit
                </button>
                <button
                  phx-click="delete_series"
                  phx-value-id={series.id}
                  data-confirm="Delete this series and all its seasons?"
                  class="btn btn-xs btn-outline btn-error"
                  data-test={"delete-series-#{series.id}"}
                >
                  Delete
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <.series_form
      :if={@show_series_form}
      form={@series_form}
      editing={@editing_series}
      series_cover_target={@series_cover_target}
      series_cover_state={@series_cover_state}
    />
    """
  end

  attr :series, :map, required: true

  defp new_season_status(assigns) do
    assigns =
      assigns
      |> assign(:active?, Content.new_season_active?(assigns.series))
      |> assign(:days_remaining, Content.days_until_new_season_expires(assigns.series))

    ~H"""
    <%= cond do %>
      <% not @active? -> %>
        <span class="text-base-content/40 text-xs">—</span>
      <% is_nil(@days_remaining) -> %>
        <span class="badge badge-sm badge-info" data-test="new-season-permanent">
          On (no expiry)
        </span>
      <% @days_remaining == 0 -> %>
        <span class="badge badge-sm badge-warning" data-test="new-season-expiring-today">
          Hides today
        </span>
      <% @days_remaining == 1 -> %>
        <span class="badge badge-sm badge-info" data-test="new-season-days-remaining">
          1 day left
        </span>
      <% true -> %>
        <span class="badge badge-sm badge-info" data-test="new-season-days-remaining">
          {@days_remaining} days left
        </span>
    <% end %>
    """
  end

  defp series_form(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-md shadow-xl">
        <h3 class="text-lg font-semibold mb-4">
          {if @editing, do: "Edit Series", else: "New Series"}
        </h3>
        <.form for={@form} phx-submit="save_series" data-test="series-form">
          <div class="mb-4">
            <label class="label" for="series-title">Title</label>
            <input
              type="text"
              id="series-title"
              name="series[title]"
              value={@form[:title].value}
              required
              class="input input-bordered w-full"
              data-test="series-title-input"
            />
            <.field_error :for={msg <- error_messages(@form[:title])}>
              {msg}
            </.field_error>
          </div>
          <div class="mb-4">
            <label class="label" for="series-description">Description</label>
            <textarea
              id="series-description"
              name="series[description]"
              class="textarea textarea-bordered w-full"
              rows="3"
            >{@form[:description].value}</textarea>
          </div>
          <div class="mb-4">
            <BobineWeb.Components.AdminComponents.image_upload_field
              name="series[cover_image_url]"
              kind="series_cover"
              target_id={@series_cover_target}
              url={@series_cover_state.url}
              status={@series_cover_state.status}
              percent={@series_cover_state.percent}
              error={@series_cover_state.error}
              label="Cover image"
              help="JPG, PNG or WebP. Used for cards and hero slides."
            />
          </div>
          <div class="mb-4">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="hidden"
                name="series[visible]"
                value="false"
              />
              <input
                type="checkbox"
                name="series[visible]"
                value="true"
                checked={@form[:visible].value != false}
                class="checkbox"
                data-test="series-visible-input"
              /> Visible to viewers
            </label>
          </div>
          <div class="mb-4">
            <label
              class="label cursor-pointer justify-start gap-3"
              data-test="new-season-toggle"
            >
              <input type="hidden" name="series[new_season]" value="false" />
              <input
                type="checkbox"
                name="series[new_season]"
                value="true"
                checked={@form[:new_season].value == true}
                class="checkbox"
                data-test="series-new-season-input"
              /> Show "New Season" badge
            </label>
            <p class="text-xs text-base-content/60 mt-2">
              Optionally pick a date to automatically hide the badge after that day.
              Leave blank to keep it shown until you uncheck the box.
            </p>
            <input
              type="date"
              name="series[new_season_expires_at]"
              value={format_date_value(@form[:new_season_expires_at].value)}
              min={Date.utc_today() |> Date.to_iso8601()}
              class="input input-bordered w-full mt-2"
              data-test="series-new-season-expires-input"
            />
          </div>
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel_series_form" class="btn btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary" data-test="save-series-btn">
              Save
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp series_detail_view(assigns) do
    ~H"""
    <div class="flex items-center justify-between pb-4">
      <div class="flex items-center gap-3">
        <button
          phx-click="back_to_series_list"
          class="btn btn-ghost btn-sm"
          data-test="back-to-series-list"
        >
          ← Back
        </button>
        <.header>{@series.title}</.header>
      </div>
      <button
        :if={@can_manage}
        phx-click="new_season"
        class="btn btn-primary btn-sm"
        data-test="new-season-btn"
      >
        New Season
      </button>
    </div>

    <div :if={@series.description} class="mb-4 text-base-content/70">
      {@series.description}
    </div>

    <div
      :if={@seasons == []}
      class="py-8 text-center text-base-content/60"
      data-test="seasons-empty"
    >
      <p>No seasons in this series yet.</p>
    </div>

    <div :if={@seasons != []} data-test="seasons-list" class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr>
            <th>#</th>
            <th>Title</th>
            <th>Episodes</th>
            <th>Visible</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={season <- @seasons} data-test={"season-row-#{season.id}"}>
            <td class="font-mono">{season.season_number}</td>
            <td>
              <.link
                navigate={~p"/admin/series/#{@series.id}/seasons/#{season.id}"}
                class="font-medium hover:text-primary hover:underline"
                data-test={"open-season-#{season.id}"}
              >
                {season.title}
              </.link>
              <div class="text-xs text-base-content/60 font-mono">{season.slug}</div>
            </td>
            <td>{season.episode_count}</td>
            <td>
              <button
                :if={@can_manage}
                phx-click="toggle_season_visibility"
                phx-value-id={season.id}
                data-test={"season-visibility-#{season.id}"}
                class={"badge badge-sm #{if season.visible, do: "badge-success", else: "badge-ghost"}"}
              >
                {if season.visible, do: "Visible", else: "Hidden"}
              </button>
              <span :if={!@can_manage} class="badge badge-sm badge-ghost">
                {if season.visible, do: "Visible", else: "Hidden"}
              </span>
            </td>
            <td :if={@can_manage}>
              <div class="flex gap-1">
                <button
                  phx-click="edit_season"
                  phx-value-id={season.id}
                  class="btn btn-xs btn-outline"
                  data-test={"edit-season-#{season.id}"}
                >
                  Edit
                </button>
                <button
                  phx-click="delete_season"
                  phx-value-id={season.id}
                  data-confirm="Delete this season?"
                  class="btn btn-xs btn-outline btn-error"
                  data-test={"delete-season-#{season.id}"}
                >
                  Delete
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <.season_form
      :if={@show_season_form}
      form={@season_form}
      editing={@editing_season}
      season_cover_target={@season_cover_target}
      season_cover_state={@season_cover_state}
    />
    """
  end

  defp season_form(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div class="bg-base-100 rounded-lg p-6 w-full max-w-md shadow-xl">
        <h3 class="text-lg font-semibold mb-4">
          {if @editing, do: "Edit Season", else: "New Season"}
        </h3>
        <.form for={@form} phx-submit="save_season" data-test="season-form">
          <div class="mb-4">
            <label class="label" for="season-title">Title (optional)</label>
            <input
              type="text"
              id="season-title"
              name="season[title]"
              value={@form[:title].value}
              placeholder="Leave blank to auto-name (e.g. ‘Season 1’)"
              class="input input-bordered w-full"
              data-test="season-title-input"
            />
            <.field_error :for={msg <- error_messages(@form[:title])}>
              {msg}
            </.field_error>
          </div>
          <div class="mb-4">
            <label class="label" for="season-number">Season Number</label>
            <input
              type="number"
              id="season-number"
              name="season[season_number]"
              value={@form[:season_number].value}
              min="1"
              class="input input-bordered w-full"
              data-test="season-number-input"
            />
            <p class="text-xs text-base-content/60 mt-1">
              Leave blank to auto-assign the next number.
            </p>
            <.field_error :for={msg <- error_messages(@form[:season_number])}>
              {msg}
            </.field_error>
          </div>
          <div class="mb-4">
            <label class="label" for="season-description">Description</label>
            <textarea
              id="season-description"
              name="season[description]"
              class="textarea textarea-bordered w-full"
              rows="3"
            >{@form[:description].value}</textarea>
          </div>
          <div class="mb-4">
            <BobineWeb.Components.AdminComponents.image_upload_field
              name="season[cover_image_url]"
              kind="season_cover"
              target_id={@season_cover_target}
              url={@season_cover_state.url}
              status={@season_cover_state.status}
              percent={@season_cover_state.percent}
              error={@season_cover_state.error}
              label="Cover image"
              help="JPG, PNG or WebP. Optional — falls back to the first episode's thumbnail."
            />
          </div>
          <div class="mb-4">
            <label class="label cursor-pointer justify-start gap-3">
              <input type="hidden" name="season[visible]" value="false" />
              <input
                type="checkbox"
                name="season[visible]"
                value="true"
                checked={@form[:visible].value != false}
                class="checkbox"
                data-test="season-visible-input"
              /> Visible to viewers
            </label>
          </div>
          <div class="flex justify-end gap-2">
            <button type="button" phx-click="cancel_season_form" class="btn btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary" data-test="save-season-btn">
              Save
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  ## -----------------------------------------------------------------------
  ## Private helpers
  ## -----------------------------------------------------------------------

  defp load_series(socket) do
    org = socket.assigns.organization
    %{results: series_list} = Content.list_series(org, per_page: 100)
    assign(socket, :series_list, series_list)
  end

  # Strip blank season_number so the context's auto-assign logic kicks in.
  defp drop_blank_season_number(%{"season_number" => ""} = params),
    do: Map.delete(params, "season_number")

  defp drop_blank_season_number(params), do: params

  # Strip blank title so create_season's default-title logic kicks in.
  defp drop_blank_title(%{"title" => title} = params) when is_binary(title) do
    if String.trim(title) == "", do: Map.delete(params, "title"), else: params
  end

  defp drop_blank_title(params), do: params

  defp load_seasons(socket) do
    org = socket.assigns.organization
    series = socket.assigns.selected_series
    %{results: seasons} = Content.list_seasons(org, series, per_page: 100)
    assign(socket, :seasons, seasons)
  end

  # Form-side normalisation for the New Season fields:
  #
  #   * If the new_season checkbox is unchecked, force expiry to nil so the
  #     schema's `maybe_clear_new_season_expiry/1` doesn't have to guess.
  #   * If the date input is blank, drop it so it stays nil (= "no expiry").
  #   * If a date is provided, convert "YYYY-MM-DD" to a UTC end-of-day
  #     DateTime so the badge stays visible all day on the chosen date.
  defp normalize_new_season_params(params) do
    params
    |> normalize_expiry_date()
    |> clear_expiry_when_flag_off()
  end

  defp normalize_expiry_date(%{"new_season_expires_at" => ""} = params),
    do: Map.delete(params, "new_season_expires_at")

  defp normalize_expiry_date(%{"new_season_expires_at" => date_string} = params)
       when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        end_of_day = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        Map.put(params, "new_season_expires_at", end_of_day)

      _ ->
        Map.delete(params, "new_season_expires_at")
    end
  end

  defp normalize_expiry_date(params), do: params

  defp clear_expiry_when_flag_off(%{"new_season" => "false"} = params),
    do: Map.put(params, "new_season_expires_at", nil)

  defp clear_expiry_when_flag_off(params), do: params

  # Upload slot ids — stable for the whole editing session of one record.
  defp series_cover_target(nil), do: "new"
  defp series_cover_target(%Series{id: id}), do: id
  defp series_cover_target(%{id: id}), do: id

  defp season_cover_target(nil), do: "new"
  defp season_cover_target(%Season{id: id}), do: id
  defp season_cover_target(%{id: id}), do: id

  # Prefer the URL the operator actually uploaded. If nothing was uploaded,
  # don't touch the existing value (caller decides whether that's a create or
  # update). Blank strings are dropped so create_* doesn't store "".
  defp maybe_put_cover_image_url(params, nil), do: params

  defp maybe_put_cover_image_url(params, ""), do: params

  defp maybe_put_cover_image_url(params, url) when is_binary(url) do
    Map.put(params, "cover_image_url", url)
  end

  # Renders a date input value from whatever the form holds. The form may
  # carry a DateTime (after editing an existing record), an ISO date string
  # (mid-edit before normalisation), or nil.
  defp format_date_value(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_iso8601()
  defp format_date_value(value) when is_binary(value), do: value
  defp format_date_value(_), do: ""

  defp error_messages(field) do
    Enum.map(field.errors, fn {msg, _opts} -> msg end)
  end

  defp field_error(assigns) do
    ~H"""
    <p class="text-error text-sm mt-1">{render_slot(@inner_block)}</p>
    """
  end
end
