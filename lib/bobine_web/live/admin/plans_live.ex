defmodule BobineWeb.Admin.PlansLive do
  @moduledoc """
  Viewer subscription plan management. Operators create/edit/archive plans
  that viewers can subscribe to. Requires Stripe Connect to be configured.

  Events: new_plan, edit_plan, save, archive_plan, validate
  Route: /admin/plans
  """

  use BobineWeb, :live_view

  alias Bobine.Billing
  alias Bobine.Billing.Plan
  alias Phoenix.HTML.Form, as: HTMLForm

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    plans = load_plans(org)
    stripe_connected = org.stripe_connect_onboarding_complete

    {:ok,
     socket
     |> assign(:page_title, "Plans")
     |> assign(:plans, plans)
     |> assign(:stripe_connected, stripe_connected)
     |> assign(:show_form, false)
     |> assign(:editing_plan, nil)
     |> assign_form(Billing.change_plan(%Plan{}, %{}))}
  end

  @impl true
  def handle_event("new_plan", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_plan, nil)
     |> assign_form(Billing.change_plan(%Plan{}, %{}))}
  end

  @impl true
  def handle_event("edit_plan", %{"id" => id}, socket) do
    org = socket.assigns.organization
    plan = Billing.get_plan!(org, id)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_plan, plan)
     |> assign_form(Billing.change_plan(plan, %{}))}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, editing_plan: nil)}
  end

  @impl true
  def handle_event("validate", %{"plan" => plan_params}, socket) do
    plan = socket.assigns.editing_plan || %Plan{}

    changeset =
      plan
      |> Billing.change_plan(plan_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save_plan", %{"plan" => plan_params}, socket) do
    org = socket.assigns.organization

    plan_params =
      plan_params
      |> parse_amount()
      |> parse_interval()
      |> parse_trial_days()
      |> parse_features()

    case socket.assigns.editing_plan do
      nil -> create_plan(socket, org, stringify_keys(plan_params))
      plan -> update_plan(socket, org, plan, stringify_keys(plan_params))
    end
  end

  @impl true
  def handle_event("deactivate_plan", %{"id" => id}, socket) do
    org = socket.assigns.organization
    plan = Billing.get_plan!(org, id)

    case Billing.deactivate_plan(plan) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> assign(:plans, load_plans(org))
         |> put_flash(:info, "Plan deactivated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not deactivate plan.")}
    end
  end

  @impl true
  def handle_event("reactivate_plan", %{"id" => id}, socket) do
    org = socket.assigns.organization
    plan = Billing.get_plan!(org, id)

    case Billing.reactivate_plan(plan) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> assign(:plans, load_plans(org))
         |> put_flash(:info, "Plan reactivated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not reactivate plan.")}
    end
  end

  defp create_plan(socket, org, plan_params) do
    case Billing.create_plan_with_stripe(org, plan_params) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> assign(:plans, load_plans(org))
         |> assign(:show_form, false)
         |> put_flash(:info, "Plan created.")}

      {:error, :stripe_not_connected} ->
        {:noreply, put_flash(socket, :error, "Connect your Stripe account first.")}

      {:error, :stripe_error, _reason} ->
        {:noreply, put_flash(socket, :error, "Stripe error. Please try again.")}

      {:error, :validation, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp update_plan(socket, org, plan, plan_params) do
    case Billing.update_plan_with_stripe(org, plan, plan_params) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> assign(:plans, load_plans(org))
         |> assign(:show_form, false)
         |> assign(:editing_plan, nil)
         |> put_flash(:info, "Plan updated.")}

      {:error, :stripe_not_connected} ->
        {:noreply, put_flash(socket, :error, "Connect your Stripe account first.")}

      {:error, :stripe_error, _reason} ->
        {:noreply, put_flash(socket, :error, "Stripe error. Please try again.")}

      {:error, :validation, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp load_plans(org) do
    %{results: plans} = Billing.list_plans(org, per_page: 100)
    plans
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp parse_amount(%{"amount_dollars" => dollars} = params) when is_binary(dollars) do
    case Float.parse(dollars) do
      {value, _} -> Map.put(params, "amount", round(value * 100))
      :error -> params
    end
  end

  defp parse_amount(params), do: params

  defp parse_interval(%{"interval" => interval} = params)
       when interval in ["monthly", "yearly"] do
    Map.put(params, "interval", String.to_existing_atom(interval))
  end

  defp parse_interval(params), do: params

  defp parse_trial_days(%{"trial_period_days" => ""} = params),
    do: Map.put(params, "trial_period_days", nil)

  defp parse_trial_days(%{"trial_period_days" => days} = params) when is_binary(days) do
    case Integer.parse(days) do
      {n, _} -> Map.put(params, "trial_period_days", n)
      :error -> params
    end
  end

  defp parse_trial_days(params), do: params

  defp parse_features(%{"features_text" => text} = params) when is_binary(text) do
    features =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(params, "features", features)
  end

  defp parse_features(params), do: params

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

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
        title="Plans"
        subtitle="Viewer subscription tiers backed by Stripe Connect."
      >
        <:actions>
          <BobineWeb.Components.AdminUI.admin_button
            :if={@stripe_connected}
            phx-click="new_plan"
            size={:sm}
            data-test="new-plan-btn"
          >
            New plan
          </BobineWeb.Components.AdminUI.admin_button>
        </:actions>

        <div
          :if={!@stripe_connected}
          class="rounded-lg border border-warning/50 bg-warning/10 px-4 py-3 font-body text-sm text-admin-fg"
          data-test="stripe-required-warning"
        >
          Connect your Stripe account in
          <.link href="/admin/settings" class="text-admin-accent underline">Settings</.link>
          before creating plans.
        </div>

        <BobineWeb.Components.AdminUI.admin_empty
          :if={@plans == []}
          title="No plans yet"
          description="Create one to start accepting viewer subscriptions."
          data_test="plans-empty"
        />

        <div :if={@plans != []} class="space-y-3" data-test="plans-list">
          <div
            :for={plan <- @plans}
            class={[
              "rounded-lg border border-admin-border bg-admin-card p-4 flex items-center justify-between",
              !plan.active && "opacity-60"
            ]}
            data-test={"plan-row-#{plan.id}"}
          >
            <div>
              <div class="flex items-center gap-2">
                <span class="font-display font-semibold text-admin-fg">{plan.name}</span>
                <span
                  :if={!plan.active}
                  class="rounded-full border border-admin-border px-2 py-0.5 font-ui text-xs text-admin-muted"
                >
                  Inactive
                </span>
                <span
                  :if={plan.trial_period_days && plan.trial_period_days > 0}
                  class="rounded-full bg-admin-accent/10 px-2 py-0.5 font-ui text-xs text-admin-accent"
                >
                  {plan.trial_period_days}-day trial
                </span>
              </div>
              <p class="font-mono text-sm text-admin-muted mt-1">
                ${format_dollars(plan.amount)}/{plan.interval}
                <span :if={plan.currency != "usd"} class="uppercase">{plan.currency}</span>
              </p>
            </div>

            <div class="flex gap-1">
              <BobineWeb.Components.AdminUI.admin_button
                variant={:ghost}
                size={:sm}
                phx-click="edit_plan"
                phx-value-id={plan.id}
                data-test={"edit-plan-#{plan.id}"}
              >
                Edit
              </BobineWeb.Components.AdminUI.admin_button>
              <BobineWeb.Components.AdminUI.admin_button
                :if={plan.active}
                variant={:ghost}
                size={:sm}
                phx-click="deactivate_plan"
                phx-value-id={plan.id}
                data-test={"deactivate-plan-#{plan.id}"}
              >
                Deactivate
              </BobineWeb.Components.AdminUI.admin_button>
              <BobineWeb.Components.AdminUI.admin_button
                :if={!plan.active}
                variant={:ghost}
                size={:sm}
                phx-click="reactivate_plan"
                phx-value-id={plan.id}
                data-test={"reactivate-plan-#{plan.id}"}
              >
                Reactivate
              </BobineWeb.Components.AdminUI.admin_button>
            </div>
          </div>
        </div>
      </BobineWeb.Components.AdminUI.admin_panel>

      <BobineWeb.Components.AdminUI.admin_sheet
        id="plan-sheet"
        open={@show_form}
        title={if @editing_plan, do: "Edit plan", else: "New plan"}
        subtitle="Syncs to Stripe on save."
        on_close="cancel_form"
        data_test="plan-form"
      >
        <.form
          for={@form}
          id="plan-form"
          phx-change="validate"
          phx-submit="save_plan"
          class="space-y-4"
        >
          <.input field={@form[:name]} type="text" label="Name" required data-test="plan-name-input" />
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            data-test="plan-description-input"
          />

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label
                class="block font-ui text-sm font-medium text-admin-fg mb-1"
                for="plan_amount_dollars"
              >
                Price (dollars)
              </label>
              <input
                type="number"
                id="plan_amount_dollars"
                name="plan[amount_dollars]"
                step="0.01"
                min="0"
                value={if @editing_plan, do: format_dollars(@editing_plan.amount), else: ""}
                class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-mono text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
                required
                data-test="plan-amount-input"
              />
              <p
                :if={@editing_plan && price_will_change?(@editing_plan, @form)}
                class="font-body text-xs text-warning mt-1"
              >
                Changing the price will create a new Stripe Price. Existing subscribers keep their current price.
              </p>
            </div>
            <.input
              field={@form[:interval]}
              type="select"
              label="Interval"
              options={[{"Monthly", "monthly"}, {"Yearly", "yearly"}]}
              required
              data-test="plan-interval-select"
            />
          </div>

          <.input
            field={@form[:trial_period_days]}
            type="number"
            label="Trial period (days)"
            min="0"
            data-test="plan-trial-days-input"
          />

          <div>
            <label
              class="block font-ui text-sm font-medium text-admin-fg mb-1"
              for="plan_features_text"
            >
              Features (one per line)
            </label>
            <textarea
              id="plan_features_text"
              name="plan[features_text]"
              rows="4"
              class="w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
              data-test="plan-features-input"
            >{if @editing_plan, do: Enum.join(@editing_plan.features, "\n"), else: ""}</textarea>
          </div>
        </.form>

        <:footer>
          <BobineWeb.Components.AdminUI.admin_button
            variant={:ghost}
            phx-click="cancel_form"
          >
            Cancel
          </BobineWeb.Components.AdminUI.admin_button>
          <BobineWeb.Components.AdminUI.admin_button
            type="submit"
            form="plan-form"
            data-test="plan-save-btn"
          >
            Save
          </BobineWeb.Components.AdminUI.admin_button>
        </:footer>
      </BobineWeb.Components.AdminUI.admin_sheet>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp format_dollars(nil), do: "0.00"

  defp format_dollars(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remaining = rem(cents, 100)
    "#{dollars}.#{String.pad_leading(Integer.to_string(remaining), 2, "0")}"
  end

  defp price_will_change?(plan, form) do
    amount_str = HTMLForm.input_value(form.source, :amount_dollars)

    case amount_str do
      nil ->
        false

      "" ->
        false

      val when is_binary(val) ->
        case Float.parse(val) do
          {v, _} -> round(v * 100) != plan.amount
          :error -> false
        end

      _ ->
        false
    end
  end
end
