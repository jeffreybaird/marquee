defmodule BobineWeb.Admin.CouponsLive do
  @moduledoc """
  Coupon management. Create/list Stripe coupons for viewer subscriptions.
  Requires Stripe Connect. Supports percent and fixed-amount discounts.

  Events: new_coupon, save, delete_coupon
  Route: /admin/coupons
  """

  use BobineWeb, :live_view

  alias Bobine.Billing
  alias Bobine.Billing.Coupon

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    coupons = load_coupons(org)

    {:ok,
     socket
     |> assign(:page_title, "Coupons")
     |> assign(:coupons, coupons)
     |> assign(:stripe_connected, org.stripe_connect_onboarding_complete)
     |> assign(:show_form, false)
     |> assign(:discount_type, "percent")
     |> assign_form(Billing.change_coupon(%Coupon{}, %{}))}
  end

  @impl true
  def handle_event("new_coupon", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:discount_type, "percent")
     |> assign_form(Billing.change_coupon(%Coupon{}, %{}))}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false)}
  end

  @impl true
  def handle_event("toggle_discount_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :discount_type, type)}
  end

  @impl true
  def handle_event("save_coupon", %{"coupon" => coupon_params}, socket) do
    org = socket.assigns.organization

    attrs = parse_coupon_params(coupon_params, socket.assigns.discount_type)

    case Billing.create_coupon(org, attrs) do
      {:ok, _coupon} ->
        {:noreply,
         socket
         |> assign(:coupons, load_coupons(org))
         |> assign(:show_form, false)
         |> put_flash(:info, "Coupon created.")}

      {:error, :stripe_not_connected} ->
        {:noreply, put_flash(socket, :error, "Connect your Stripe account first.")}

      {:error, :stripe_error, _reason} ->
        {:noreply, put_flash(socket, :error, "Stripe error. Please try again.")}

      {:error, :validation, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("deactivate_coupon", %{"id" => id}, socket) do
    org = socket.assigns.organization

    coupon =
      load_coupons(org)
      |> Enum.find(&(&1.id == id))

    if coupon do
      case Billing.deactivate_coupon(coupon) do
        {:ok, _coupon} ->
          {:noreply,
           socket
           |> assign(:coupons, load_coupons(org))
           |> put_flash(:info, "Coupon deactivated.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not deactivate coupon.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Coupon not found.")}
    end
  end

  defp load_coupons(org) do
    %{results: coupons} = Billing.list_coupons(org, per_page: 100)
    coupons
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp parse_coupon_params(params, discount_type) do
    base = %{
      code: params["code"],
      name: params["name"],
      duration: params["duration"],
      duration_in_months: parse_int(params["duration_in_months"]),
      max_redemptions: parse_int(params["max_redemptions"])
    }

    case discount_type do
      "percent" ->
        Map.put(base, :percent_off, parse_decimal(params["percent_off"]))

      "amount" ->
        base
        |> Map.put(:amount_off, parse_cents(params["amount_off_dollars"]))
        |> Map.put(:currency, params["currency"] || "usd")
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp parse_cents(nil), do: nil
  defp parse_cents(""), do: nil

  defp parse_cents(val) when is_binary(val) do
    case Float.parse(val) do
      {v, _} -> round(v * 100)
      :error -> nil
    end
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
        title="Coupons"
        subtitle="Stripe-backed discount codes for viewer subscriptions."
      >
        <:actions>
          <BobineWeb.Components.AdminUI.admin_button
            :if={@stripe_connected}
            phx-click="new_coupon"
            size={:sm}
            data-test="new-coupon-btn"
          >
            New coupon
          </BobineWeb.Components.AdminUI.admin_button>
        </:actions>

        <div
          :if={!@stripe_connected}
          class="rounded-lg border border-warning/50 bg-warning/10 px-4 py-3 font-body text-sm text-text-primary"
          data-test="stripe-required-warning"
        >
          Connect your Stripe account in
          <.link href="/admin/settings" class="text-accent underline">Settings</.link>
          before creating coupons.
        </div>

        <BobineWeb.Components.AdminUI.admin_empty
          :if={@coupons == []}
          title="No coupons yet"
          description="Create a coupon to offer viewers a discount on their subscription."
          data_test="coupons-empty"
        />

        <div :if={@coupons != []} class="space-y-3" data-test="coupons-list">
          <div
            :for={coupon <- @coupons}
            class={[
              "rounded-lg border border-border bg-surface p-4 flex items-center justify-between",
              !coupon.active && "opacity-60"
            ]}
            data-test={"coupon-row-#{coupon.id}"}
          >
            <div>
              <div class="flex items-center gap-2">
                <code class="font-mono font-semibold text-text-primary">{coupon.code}</code>
                <span
                  :if={!coupon.active}
                  class="rounded-full border border-border px-2 py-0.5 font-ui text-xs text-text-muted"
                >
                  Inactive
                </span>
              </div>
              <p class="font-body text-sm text-text-secondary mt-1">
                <span class="font-mono">{format_discount(coupon)}</span>
                &middot; {coupon.duration}
                <span :if={coupon.max_redemptions}>
                  &middot; max <span class="font-mono">{coupon.max_redemptions}</span> uses
                </span>
              </p>
            </div>

            <div class="flex gap-1">
              <BobineWeb.Components.AdminUI.admin_button
                :if={coupon.active}
                variant={:ghost}
                size={:sm}
                phx-click="deactivate_coupon"
                phx-value-id={coupon.id}
                class="text-warning"
                data-test={"deactivate-coupon-#{coupon.id}"}
              >
                Deactivate
              </BobineWeb.Components.AdminUI.admin_button>
            </div>
          </div>
        </div>
      </BobineWeb.Components.AdminUI.admin_panel>

      <BobineWeb.Components.AdminUI.admin_sheet
        id="coupon-sheet"
        open={@show_form}
        title="New coupon"
        subtitle="Syncs to Stripe on save."
        on_close="cancel_form"
        data_test="coupon-form"
      >
        <.form for={@form} id="coupon-form" phx-submit="save_coupon" class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label
                class="block font-ui text-sm font-medium text-text-primary mb-1"
                for="coupon_code"
              >
                Code
              </label>
              <input
                type="text"
                id="coupon_code"
                name="coupon[code]"
                class="w-full rounded-md border border-border bg-elevated px-3 py-2 font-mono text-sm uppercase text-text-primary focus:border-accent focus:outline-none"
                required
                placeholder="LAUNCH50"
                data-test="coupon-code-input"
              />
            </div>
            <div>
              <label
                class="block font-ui text-sm font-medium text-text-primary mb-1"
                for="coupon_name"
              >
                Name
              </label>
              <input
                type="text"
                id="coupon_name"
                name="coupon[name]"
                class="w-full rounded-md border border-border bg-elevated px-3 py-2 font-body text-sm text-text-primary focus:border-accent focus:outline-none"
                placeholder="Launch discount"
                data-test="coupon-name-input"
              />
            </div>
          </div>

          <div>
            <label class="block font-ui text-sm font-medium text-text-primary mb-1">
              Discount type
            </label>
            <div class="flex gap-2">
              <BobineWeb.Components.AdminUI.admin_button
                type="button"
                variant={if @discount_type == "percent", do: :accent, else: :ghost}
                size={:sm}
                phx-click="toggle_discount_type"
                phx-value-type="percent"
              >
                Percent off
              </BobineWeb.Components.AdminUI.admin_button>
              <BobineWeb.Components.AdminUI.admin_button
                type="button"
                variant={if @discount_type == "amount", do: :accent, else: :ghost}
                size={:sm}
                phx-click="toggle_discount_type"
                phx-value-type="amount"
              >
                Amount off
              </BobineWeb.Components.AdminUI.admin_button>
            </div>
          </div>

          <div :if={@discount_type == "percent"}>
            <label
              class="block font-ui text-sm font-medium text-text-primary mb-1"
              for="coupon_percent_off"
            >
              Percent off
            </label>
            <input
              type="number"
              id="coupon_percent_off"
              name="coupon[percent_off]"
              min="1"
              max="100"
              step="1"
              class="w-full rounded-md border border-border bg-elevated px-3 py-2 font-mono text-sm text-text-primary focus:border-accent focus:outline-none"
              required
              data-test="coupon-percent-off-input"
            />
          </div>

          <div :if={@discount_type == "amount"}>
            <label
              class="block font-ui text-sm font-medium text-text-primary mb-1"
              for="coupon_amount_off"
            >
              Amount off (dollars)
            </label>
            <input
              type="number"
              id="coupon_amount_off"
              name="coupon[amount_off_dollars]"
              min="0.01"
              step="0.01"
              class="w-full rounded-md border border-border bg-elevated px-3 py-2 font-mono text-sm text-text-primary focus:border-accent focus:outline-none"
              required
              data-test="coupon-amount-off-input"
            />
          </div>

          <.input
            field={@form[:duration]}
            type="select"
            label="Duration"
            options={[{"Once", "once"}, {"Repeating", "repeating"}, {"Forever", "forever"}]}
            required
            name="coupon[duration]"
            data-test="coupon-duration-select"
          />

          <div>
            <label
              class="block font-ui text-sm font-medium text-text-primary mb-1"
              for="coupon_duration_in_months"
            >
              Duration in months (for repeating)
            </label>
            <input
              type="number"
              id="coupon_duration_in_months"
              name="coupon[duration_in_months]"
              min="1"
              class="w-full rounded-md border border-border bg-elevated px-3 py-2 font-mono text-sm text-text-primary focus:border-accent focus:outline-none"
              data-test="coupon-duration-months-input"
            />
          </div>

          <div>
            <label
              class="block font-ui text-sm font-medium text-text-primary mb-1"
              for="coupon_max_redemptions"
            >
              Max redemptions (optional)
            </label>
            <input
              type="number"
              id="coupon_max_redemptions"
              name="coupon[max_redemptions]"
              min="1"
              class="w-full rounded-md border border-border bg-elevated px-3 py-2 font-mono text-sm text-text-primary focus:border-accent focus:outline-none"
              data-test="coupon-max-redemptions-input"
            />
          </div>
        </.form>

        <:footer>
          <BobineWeb.Components.AdminUI.admin_button variant={:ghost} phx-click="cancel_form">
            Cancel
          </BobineWeb.Components.AdminUI.admin_button>
          <BobineWeb.Components.AdminUI.admin_button
            type="submit"
            form="coupon-form"
            data-test="coupon-save-btn"
          >
            Create coupon
          </BobineWeb.Components.AdminUI.admin_button>
        </:footer>
      </BobineWeb.Components.AdminUI.admin_sheet>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp format_discount(%{percent_off: pct}) when not is_nil(pct), do: "#{pct}% off"

  defp format_discount(%{amount_off: amt, currency: cur}) when not is_nil(amt) do
    "$#{div(amt, 100)}.#{String.pad_leading(Integer.to_string(rem(amt, 100)), 2, "0")} off #{String.upcase(cur || "usd")}"
  end

  defp format_discount(_), do: ""
end
