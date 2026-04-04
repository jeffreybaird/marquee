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
      <div class="flex items-center justify-between mb-6">
        <.header>Plans</.header>
        <button
          :if={@stripe_connected && !@show_form}
          phx-click="new_plan"
          class="btn btn-primary btn-sm"
          data-test="new-plan-btn"
        >
          New plan
        </button>
      </div>

      <div :if={!@stripe_connected} class="alert alert-warning" data-test="stripe-required-warning">
        <p>
          Connect your Stripe account in <a href="/admin/settings" class="link">Settings</a>
          before creating plans.
        </p>
      </div>

      <%!-- Plan form --%>
      <div :if={@show_form} class="mb-8 rounded-lg border border-base-300 p-6" data-test="plan-form">
        <h3 class="text-lg font-semibold mb-4">
          {if @editing_plan, do: "Edit plan", else: "New plan"}
        </h3>

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
              <label class="label" for="plan_amount_dollars">
                <span class="label-text">Price (dollars)</span>
              </label>
              <input
                type="number"
                id="plan_amount_dollars"
                name="plan[amount_dollars]"
                step="0.01"
                min="0"
                value={if @editing_plan, do: format_dollars(@editing_plan.amount), else: ""}
                class="input input-bordered w-full"
                required
                data-test="plan-amount-input"
              />
              <p
                :if={@editing_plan && price_will_change?(@editing_plan, @form)}
                class="text-warning text-xs mt-1"
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
            <label class="label" for="plan_features_text">
              <span class="label-text">Features (one per line)</span>
            </label>
            <textarea
              id="plan_features_text"
              name="plan[features_text]"
              rows="4"
              class="textarea textarea-bordered w-full"
              data-test="plan-features-input"
            >{if @editing_plan, do: Enum.join(@editing_plan.features, "\n"), else: ""}</textarea>
          </div>

          <div class="flex gap-2 mt-4">
            <button type="submit" class="btn btn-primary" data-test="plan-save-btn">Save</button>
            <button type="button" phx-click="cancel_form" class="btn btn-ghost">Cancel</button>
          </div>
        </.form>
      </div>

      <%!-- Plans list --%>
      <div
        :if={@plans == [] && !@show_form}
        class="text-center py-12 text-base-content/60"
        data-test="plans-empty"
      >
        <p>No plans yet. Create one to start accepting viewer subscriptions.</p>
      </div>

      <div :if={@plans != []} class="space-y-3" data-test="plans-list">
        <div
          :for={plan <- @plans}
          class={[
            "rounded-lg border p-4 flex items-center justify-between",
            if(!plan.active, do: "opacity-60 border-base-300", else: "border-base-300")
          ]}
          data-test={"plan-row-#{plan.id}"}
        >
          <div>
            <div class="flex items-center gap-2">
              <span class="font-semibold">{plan.name}</span>
              <span :if={!plan.active} class="badge badge-sm badge-ghost">Inactive</span>
              <span
                :if={plan.trial_period_days && plan.trial_period_days > 0}
                class="badge badge-sm badge-info"
              >
                {plan.trial_period_days}-day trial
              </span>
            </div>
            <p class="text-sm text-base-content/70 mt-1">
              ${format_dollars(plan.amount)}/{plan.interval}
              <span :if={plan.currency != "usd"} class="uppercase">{plan.currency}</span>
            </p>
          </div>

          <div class="flex gap-2">
            <button
              phx-click="edit_plan"
              phx-value-id={plan.id}
              class="btn btn-sm btn-ghost"
              data-test={"edit-plan-#{plan.id}"}
            >
              Edit
            </button>
            <button
              :if={plan.active}
              phx-click="deactivate_plan"
              phx-value-id={plan.id}
              class="btn btn-sm btn-ghost text-warning"
              data-test={"deactivate-plan-#{plan.id}"}
            >
              Deactivate
            </button>
            <button
              :if={!plan.active}
              phx-click="reactivate_plan"
              phx-value-id={plan.id}
              class="btn btn-sm btn-ghost text-success"
              data-test={"reactivate-plan-#{plan.id}"}
            >
              Reactivate
            </button>
          </div>
        </div>
      </div>
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
