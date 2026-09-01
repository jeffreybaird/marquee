defmodule MarqueeWeb.Admin.LiveEventLive.New do
  @moduledoc """
  Form for creating a new live event. Provisions a Mux live stream on save.

  Route: GET /admin/live-events/new
  """

  use MarqueeWeb, :live_view

  alias Marquee.Streaming
  alias Marquee.Streaming.LiveEvent

  @impl true
  def mount(_params, _session, socket) do
    changeset = LiveEvent.changeset(%LiveEvent{}, %{})

    {:ok,
     socket
     |> assign(:page_title, "New Live Event")
     |> assign(:form, to_form(changeset, as: "live_event"))
     |> assign(:access_type, "subscribers_only")}
  end

  @impl true
  def handle_event("validate", %{"live_event" => params}, socket) do
    changeset =
      %LiveEvent{}
      |> LiveEvent.changeset(params)
      |> Map.put(:action, :validate)

    access_type = Map.get(params, "access_type", "subscribers_only")

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: "live_event"))
     |> assign(:access_type, access_type)}
  end

  @impl true
  def handle_event("generate_slug", %{"title" => title}, socket) do
    slug = slugify(title)
    params = socket.assigns.form.params |> Map.put("slug", slug)
    changeset = LiveEvent.changeset(%LiveEvent{}, params) |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: "live_event"))}
  end

  @impl true
  def handle_event("save", %{"live_event" => params}, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns.organization

    params =
      params
      |> convert_ppv_price_to_cents()
      |> Map.put("organization_id", org.id)

    case Streaming.create_live_event(scope, params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Live event created.")
         |> push_navigate(to: ~p"/admin/live-events/#{event.slug}")}

      {:error, :validation, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: "live_event"))
         |> put_flash(:error, "Please fix the errors below.")}

      {:error, :mux_error, _details} ->
        {:noreply, put_flash(socket, :error, "Could not provision Mux stream. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
      flash={@flash}
    >
      <.header>
        New Live Event
        <:subtitle>Create a new live streaming event.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="live-event-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-6"
        data-test="live-event-form"
      >
        <.input
          field={@form[:title]}
          type="text"
          label="Title"
          required
          phx-blur="generate_slug"
          phx-value-title={@form[:title].value}
          data-test="title-input"
        />

        <.input
          field={@form[:slug]}
          type="text"
          label="Slug"
          required
          placeholder="auto-generated from title"
          data-test="slug-input"
        />

        <.input
          field={@form[:description]}
          type="textarea"
          label="Description"
          rows={4}
          data-test="description-input"
        />

        <.input
          field={@form[:scheduled_start_at]}
          type="datetime-local"
          label="Scheduled Start"
          required
          data-test="scheduled-start-input"
        />

        <.input
          field={@form[:estimated_duration_minutes]}
          type="number"
          label="Estimated Duration (minutes)"
          min="1"
          data-test="duration-input"
        />

        <.input
          field={@form[:cover_image_url]}
          type="url"
          label="Cover Image URL"
          data-test="cover-image-input"
        />

        <div>
          <label for="live_event_access_type" class="block text-sm font-medium text-admin-fg">
            Access Type <span aria-hidden="true">*</span>
          </label>
          <select
            id="live_event_access_type"
            name="live_event[access_type]"
            required
            aria-required="true"
            class="mt-1 block w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            data-test="access-type-select"
          >
            <option value="subscribers_only" selected={@access_type == "subscribers_only"}>
              Subscribers Only
            </option>
            <option value="public" selected={@access_type == "public"}>Public</option>
            <option value="pay_per_view" selected={@access_type == "pay_per_view"}>
              Pay Per View
            </option>
          </select>
          <p
            :for={
              msg <-
                Enum.map(
                  @form[:access_type].errors,
                  &MarqueeWeb.CoreComponents.translate_error(&1)
                )
            }
            class="mt-1 text-sm text-error"
          >
            {msg}
          </p>
        </div>

        <%!-- PPV fields — only shown when access_type is pay_per_view --%>
        <div :if={@access_type == "pay_per_view"} data-test="ppv-fields">
          <%!-- User inputs price in dollars; LiveView converts to cents before saving --%>
          <div>
            <label
              for="live_event_ppv_price_dollars"
              class="block text-sm font-medium text-admin-fg"
            >
              Price (USD) <span aria-hidden="true">*</span>
            </label>
            <input
              id="live_event_ppv_price_dollars"
              name="live_event[ppv_price_dollars]"
              type="number"
              step="0.01"
              min="0.01"
              required
              aria-required="true"
              placeholder="9.99"
              class="mt-1 block w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              data-test="ppv-price-input"
            />
          </div>

          <.input
            field={@form[:ppv_access_window_hours]}
            type="number"
            label="Access Window (hours)"
            min="1"
            value={@form[:ppv_access_window_hours].value || 48}
            data-test="ppv-window-input"
          />
        </div>

        <div class="flex gap-3">
          <button
            type="submit"
            class="rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-white hover:opacity-90"
            data-test="save-btn"
          >
            Create Live Event
          </button>
          <.link
            navigate={~p"/admin/live-events"}
            class="rounded-md border border-admin-border px-4 py-2 font-ui text-sm text-admin-fg hover:bg-admin-card"
            data-test="cancel-btn"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s]+/, "-")
    |> String.trim("-")
  end

  # Converts ppv_price_dollars (user-facing, string dollars) to ppv_price_cents (integer).
  # If ppv_price_dollars is absent or blank, passes params through unchanged.
  defp convert_ppv_price_to_cents(%{"ppv_price_dollars" => dollars} = params)
       when is_binary(dollars) and dollars != "" do
    case Float.parse(dollars) do
      {amount, _} ->
        cents = round(amount * 100)

        params
        |> Map.delete("ppv_price_dollars")
        |> Map.put("ppv_price_cents", cents)

      :error ->
        Map.delete(params, "ppv_price_dollars")
    end
  end

  defp convert_ppv_price_to_cents(params), do: params
end
