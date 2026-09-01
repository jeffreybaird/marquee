defmodule MarqueeWeb.Admin.LiveEventLive.Edit do
  @moduledoc """
  Form for editing an existing live event. Pre-populates all fields.

  Route: GET /admin/live-events/:slug/edit
  """

  use MarqueeWeb, :live_view

  alias Marquee.Streaming
  alias Marquee.Streaming.LiveEvent

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    org = socket.assigns.organization

    case Streaming.get_live_event_by_slug(org, slug) do
      {:ok, event} ->
        changeset = LiveEvent.changeset(event, %{})

        {:ok,
         socket
         |> assign(:page_title, "Edit: #{event.title}")
         |> assign(:event, event)
         |> assign(:form, to_form(changeset, as: "live_event"))
         |> assign(:access_type, event.access_type)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Live event not found.")
         |> push_navigate(to: ~p"/admin/live-events")}
    end
  end

  @impl true
  def handle_event("validate", %{"live_event" => params}, socket) do
    event = socket.assigns.event

    changeset =
      event
      |> LiveEvent.changeset(params)
      |> Map.put(:action, :validate)

    access_type = Map.get(params, "access_type", event.access_type)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: "live_event"))
     |> assign(:access_type, access_type)}
  end

  @impl true
  def handle_event("save", %{"live_event" => params}, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event
    params = convert_ppv_price_to_cents(params)

    case Streaming.update_live_event(scope, event, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Live event updated.")
         |> push_navigate(to: ~p"/admin/live-events/#{updated.slug}")}

      {:error, :validation, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: "live_event"))
         |> put_flash(:error, "Please fix the errors below.")}
    end
  end

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
      <.header>
        Edit Live Event
        <:subtitle>{@event.title}</:subtitle>
      </.header>

      <.form
        for={@form}
        id="live-event-edit-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-6"
        data-test="live-event-edit-form"
      >
        <.input
          field={@form[:title]}
          type="text"
          label="Title"
          required
          data-test="title-input"
        />

        <.input
          field={@form[:slug]}
          type="text"
          label="Slug"
          required
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
              value={cents_to_dollars(@event.ppv_price_cents)}
              class="mt-1 block w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              data-test="ppv-price-input"
            />
          </div>

          <.input
            field={@form[:ppv_access_window_hours]}
            type="number"
            label="Access Window (hours)"
            min="1"
            data-test="ppv-window-input"
          />
        </div>

        <div class="flex gap-3">
          <button
            type="submit"
            class="rounded-md bg-admin-accent px-4 py-2 font-ui text-sm font-medium text-white hover:opacity-90"
            data-test="save-btn"
          >
            Save Changes
          </button>
          <.link
            navigate={~p"/admin/live-events/#{@event.slug}"}
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

  # Converts ppv_price_dollars (user-facing, string dollars) to ppv_price_cents (integer).
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

  # Renders cents as a dollar string for pre-populating the edit form.
  defp cents_to_dollars(nil), do: ""

  defp cents_to_dollars(cents) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end
end
