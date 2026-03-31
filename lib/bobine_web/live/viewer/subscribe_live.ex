defmodule BobineWeb.Viewer.SubscribeLive do
  use BobineWeb, :live_view

  alias Bobine.Billing
  alias Bobine.Viewers

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    viewer = socket.assigns.current_viewer

    plans =
      if org do
        %{results: plans} = Billing.list_plans(org, per_page: 100)
        plans
      else
        []
      end

    {:ok,
     socket
     |> assign(:page_title, "Subscribe")
     |> assign(:plans, plans)
     |> assign(:viewer, viewer)}
  end

  @impl true
  def handle_event("dev_activate", _params, socket) do
    if Application.get_env(:bobine, :dev_routes, false) do
      viewer = socket.assigns.viewer
      scope = socket.assigns[:current_scope]

      case Viewers.grant_access(scope, viewer) do
        {:ok, updated_viewer} ->
          {:noreply,
           socket
           |> assign(:viewer, updated_viewer)
           |> put_flash(:info, "Subscription activated (dev mode).")
           |> push_navigate(to: ~p"/")}

        _ ->
          {:noreply, put_flash(socket, :error, "Could not activate.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_viewer={@current_viewer} organization={@organization}>
      <div class="max-w-2xl mx-auto">
        <.header>
          Choose a plan
          <:subtitle>
            {if @organization, do: "Subscribe to #{@organization.name}", else: ""}
          </:subtitle>
        </.header>

        <div :if={@plans == []} class="mt-6 p-4 bg-base-200 rounded-lg text-center">
          <p class="text-base-content/70">No plans available yet. Check back later.</p>
        </div>

        <div
          :if={@plans != []}
          class="mt-6 grid grid-cols-1 md:grid-cols-2 gap-4"
          data-test="subscribe-plan-list"
        >
          <div
            :for={plan <- @plans}
            class="bg-base-200 rounded-lg p-6 border border-base-300"
          >
            <h3 class="text-lg font-bold">{plan.name}</h3>
            <p class="mt-2 text-2xl font-bold">
              ${format_amount(plan.amount)}
              <span class="text-sm font-normal text-base-content/60">
                /{plan.interval}
              </span>
            </p>
            <button class="btn btn-primary btn-sm mt-4 w-full" disabled>
              Subscribe (coming soon)
            </button>
          </div>
        </div>

        <div
          :if={Application.get_env(:bobine, :dev_routes, false)}
          class="mt-8 p-4 border-2 border-dashed border-warning rounded-lg"
        >
          <p class="text-warning text-sm font-medium">Dev Mode</p>
          <p class="text-sm text-base-content/60 mt-1">
            Activate subscription instantly for testing.
          </p>
          <button
            phx-click="dev_activate"
            class="btn btn-warning btn-sm mt-2"
            data-test="subscribe-dev-activate-btn"
          >
            Activate (dev only)
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_amount(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remaining_cents = rem(cents, 100)
    "#{dollars}.#{String.pad_leading(Integer.to_string(remaining_cents), 2, "0")}"
  end

  defp format_amount(_), do: "0.00"
end
