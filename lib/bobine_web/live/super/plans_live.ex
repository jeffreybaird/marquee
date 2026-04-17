defmodule BobineWeb.Super.PlansLive do
  @moduledoc """
  Platform plan management. Create/edit/archive platform-level subscription
  plans that organizations subscribe to (not viewer plans).

  Events: new_plan, edit_plan, save, archive_plan, validate
  Route: /super/plans
  """

  use BobineWeb, :live_view

  alias Bobine.Billing.PlatformPlan
  alias Bobine.PlatformBilling

  @impl true
  def mount(_params, _session, socket) do
    plans = load_plans()

    {:ok,
     socket
     |> assign(:page_title, "Platform Plans")
     |> assign(:current_path, "/super/plans")
     |> assign(:current_user, socket.assigns.current_scope.user)
     |> assign(:plans, plans)
     |> assign(:editing_plan, nil)
     |> assign(:plan_form, nil)}
  end

  @impl true
  def handle_event("edit_plan", %{"id" => id}, socket) do
    plan = PlatformBilling.get_platform_plan!(id)
    form = plan_form(plan)
    {:noreply, assign(socket, editing_plan: plan, plan_form: form)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_plan: nil, plan_form: nil)}
  end

  def handle_event("save_plan", %{"platform_plan" => plan_params}, socket) do
    plan = socket.assigns.editing_plan
    scope = socket.assigns.current_scope

    case PlatformBilling.update_platform_plan(scope, plan, plan_params) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> assign(:editing_plan, nil)
         |> assign(:plan_form, nil)
         |> assign(:plans, load_plans())
         |> put_flash(:info, "Plan updated.")}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, plan_form: to_form(changeset))}

      {:error, :stripe_error, _reason} ->
        {:noreply,
         socket
         |> assign(:plan_form, plan_form(plan, plan_params))
         |> put_flash(:error, "Could not sync the plan to Stripe.")}
    end
  end

  def handle_event("deactivate_plan", %{"id" => id}, socket) do
    plan = PlatformBilling.get_platform_plan!(id)
    scope = socket.assigns.current_scope

    case PlatformBilling.deactivate_platform_plan(scope, plan) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> assign(:plans, load_plans())
         |> put_flash(:info, "Plan deactivated.")}

      {:error, _type, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not deactivate plan.")}
    end
  end

  def handle_event("new_plan", _params, socket) do
    form = plan_form(%PlatformPlan{})
    {:noreply, assign(socket, editing_plan: %PlatformPlan{}, plan_form: form)}
  end

  def handle_event("create_plan", %{"platform_plan" => plan_params}, socket) do
    scope = socket.assigns.current_scope

    case PlatformBilling.create_platform_plan(scope, plan_params) do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> assign(:editing_plan, nil)
         |> assign(:plan_form, nil)
         |> assign(:plans, load_plans())
         |> put_flash(:info, "Plan created.")}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, plan_form: to_form(changeset))}

      {:error, :stripe_error, _reason} ->
        {:noreply,
         socket
         |> assign(:plan_form, plan_form(%PlatformPlan{}, plan_params))
         |> put_flash(:error, "Could not sync the plan to Stripe.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.SuperLayout.super_layout
      current_path={@current_path}
      current_user={@current_user}
      flash={@flash}
    >
      <div class="flex items-center justify-between">
        <.header>Platform Plans</.header>
        <button
          phx-click="new_plan"
          class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content"
          data-test="new-plan-btn"
        >
          New plan
        </button>
      </div>

      <div class="mt-6" data-test="plans-list">
        <table class="w-full table-auto text-left text-sm">
          <thead class="border-b border-base-300 text-base-content/60">
            <tr>
              <th class="py-3 pr-4">Name</th>
              <th class="py-3 pr-4">Slug</th>
              <th class="py-3 pr-4">Usage</th>
              <th class="py-3 pr-4">Business</th>
              <th class="py-3 pr-4">Amount</th>
              <th class="py-3 pr-4">Active</th>
              <th class="py-3 pr-4">Highlight</th>
              <th class="py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={plan <- @plans}
              class="border-b border-base-300"
              data-test={"plan-row-#{plan.slug}"}
            >
              <td class="py-3 pr-4 font-medium text-base-content">{plan.name}</td>
              <td class="py-3 pr-4 text-base-content/70">{plan.slug}</td>
              <td class="py-3 pr-4 text-base-content/70">{plan.usage_tier}</td>
              <td class="py-3 pr-4 text-base-content/70">{plan.business_tier}</td>
              <td class="py-3 pr-4 text-base-content/70">${format_amount(plan.amount)}</td>
              <td class="py-3 pr-4">
                <span class={[
                  "inline-block rounded-full px-2 py-0.5 text-xs font-medium",
                  if(plan.active,
                    do: "bg-success/20 text-success",
                    else: "bg-base-300 text-base-content/50"
                  )
                ]}>
                  {if plan.active, do: "Active", else: "Inactive"}
                </span>
              </td>
              <td class="py-3 pr-4">
                <span class={[
                  "inline-block rounded-full px-2 py-0.5 text-xs font-medium",
                  if(plan.highlight,
                    do: "bg-primary/20 text-primary",
                    else: "bg-base-300 text-base-content/50"
                  )
                ]}>
                  {if plan.highlight, do: "Highlighted", else: "Normal"}
                </span>
              </td>
              <td class="py-3">
                <button
                  phx-click="edit_plan"
                  phx-value-id={plan.id}
                  class="mr-2 text-primary hover:underline"
                  data-test={"edit-plan-#{plan.slug}"}
                >
                  Edit
                </button>
                <button
                  :if={plan.active}
                  phx-click="deactivate_plan"
                  phx-value-id={plan.id}
                  class="text-error hover:underline"
                  data-test={"deactivate-plan-#{plan.slug}"}
                >
                  Deactivate
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%= if @editing_plan do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
          data-test="plan-edit-modal"
        >
          <div class="w-full max-w-lg rounded-lg bg-base-100 p-6 shadow-xl">
            <h3 class="text-lg font-bold text-base-content">
              {if @editing_plan.id, do: "Edit Plan", else: "New Plan"}
            </h3>
            <.form
              for={@plan_form}
              id="platform-plan-form"
              phx-submit={if @editing_plan.id, do: "save_plan", else: "create_plan"}
              class="mt-4 space-y-4"
            >
              <.input field={@plan_form[:name]} type="text" label="Name" required />
              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={@plan_form[:slug]}
                  type="text"
                  label="Slug"
                  required
                />
                <.input
                  field={@plan_form[:highlight]}
                  type="checkbox"
                  label="Highlight"
                  class="col-span-2"
                />
              </div>
              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={@plan_form[:usage_tier]}
                  type="select"
                  label="Usage Tier"
                  options={[{"Basic", :basic}, {"Super", :super}, {"Premium", :premium}]}
                  required
                />
                <.input
                  field={@plan_form[:business_tier]}
                  type="select"
                  label="Business Tier"
                  options={[
                    {"Individual", :individual},
                    {"Small Business", :small_business},
                    {"Enterprise", :enterprise}
                  ]}
                  required
                />
              </div>
              <.input
                field={@plan_form[:amount]}
                type="number"
                label="Amount (cents)"
                required
                min="0"
              />
              <.input field={@plan_form[:description]} type="textarea" label="Description" />
              <div class="grid grid-cols-3 gap-4">
                <.input
                  field={@plan_form[:max_videos]}
                  type="number"
                  label="Max Videos"
                  placeholder="unlimited"
                />
                <.input
                  field={@plan_form[:max_team_seats]}
                  type="number"
                  label="Max Seats"
                  placeholder="unlimited"
                />
                <.input
                  field={@plan_form[:max_monthly_views]}
                  type="number"
                  label="Max Views/mo"
                  placeholder="unlimited"
                />
              </div>
              <div class="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  phx-click="cancel_edit"
                  class="rounded-lg border border-base-300 px-4 py-2 text-sm font-medium text-base-content"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content"
                  data-test="save-plan-btn"
                >
                  {if @editing_plan.id, do: "Save", else: "Create"}
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </BobineWeb.Components.SuperLayout.super_layout>
    """
  end

  defp format_amount(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remaining = rem(cents, 100)
    "#{dollars}.#{String.pad_leading(Integer.to_string(remaining), 2, "0")}"
  end

  defp format_amount(_), do: "0.00"

  defp plan_form(%PlatformPlan{} = plan, attrs \\ %{}) do
    plan
    |> PlatformBilling.change_platform_plan(attrs)
    |> to_form()
  end

  defp load_plans do
    %{results: results} = PlatformBilling.list_platform_plans(include_inactive: true)
    results
  end
end
