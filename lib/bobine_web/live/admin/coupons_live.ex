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
      <div class="flex items-center justify-between mb-6">
        <.header>Coupons</.header>
        <button
          :if={@stripe_connected && !@show_form}
          phx-click="new_coupon"
          class="btn btn-primary btn-sm"
          data-test="new-coupon-btn"
        >
          New coupon
        </button>
      </div>

      <div :if={!@stripe_connected} class="alert alert-warning" data-test="stripe-required-warning">
        <p>
          Connect your Stripe account in <a href="/admin/settings" class="link">Settings</a>
          before creating coupons.
        </p>
      </div>

      <%!-- Coupon form --%>
      <div :if={@show_form} class="mb-8 rounded-lg border border-base-300 p-6" data-test="coupon-form">
        <h3 class="text-lg font-semibold mb-4">New coupon</h3>

        <.form for={@form} id="coupon-form" phx-submit="save_coupon" class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="label" for="coupon_code"><span class="label-text">Code</span></label>
              <input
                type="text"
                id="coupon_code"
                name="coupon[code]"
                class="input input-bordered w-full uppercase"
                required
                placeholder="LAUNCH50"
                data-test="coupon-code-input"
              />
            </div>
            <div>
              <label class="label" for="coupon_name"><span class="label-text">Name</span></label>
              <input
                type="text"
                id="coupon_name"
                name="coupon[name]"
                class="input input-bordered w-full"
                placeholder="Launch discount"
                data-test="coupon-name-input"
              />
            </div>
          </div>

          <%!-- Discount type toggle --%>
          <div>
            <label class="label"><span class="label-text">Discount type</span></label>
            <div class="flex gap-2">
              <button
                type="button"
                phx-click="toggle_discount_type"
                phx-value-type="percent"
                class={[
                  "btn btn-sm",
                  if(@discount_type == "percent", do: "btn-primary", else: "btn-ghost")
                ]}
              >
                Percent off
              </button>
              <button
                type="button"
                phx-click="toggle_discount_type"
                phx-value-type="amount"
                class={[
                  "btn btn-sm",
                  if(@discount_type == "amount", do: "btn-primary", else: "btn-ghost")
                ]}
              >
                Amount off
              </button>
            </div>
          </div>

          <div :if={@discount_type == "percent"}>
            <label class="label" for="coupon_percent_off">
              <span class="label-text">Percent off</span>
            </label>
            <input
              type="number"
              id="coupon_percent_off"
              name="coupon[percent_off]"
              min="1"
              max="100"
              step="1"
              class="input input-bordered w-full"
              required
              data-test="coupon-percent-off-input"
            />
          </div>

          <div :if={@discount_type == "amount"}>
            <label class="label" for="coupon_amount_off">
              <span class="label-text">Amount off (dollars)</span>
            </label>
            <input
              type="number"
              id="coupon_amount_off"
              name="coupon[amount_off_dollars]"
              min="0.01"
              step="0.01"
              class="input input-bordered w-full"
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
            <label class="label" for="coupon_duration_in_months">
              <span class="label-text">Duration in months (for repeating)</span>
            </label>
            <input
              type="number"
              id="coupon_duration_in_months"
              name="coupon[duration_in_months]"
              min="1"
              class="input input-bordered w-full"
              data-test="coupon-duration-months-input"
            />
          </div>

          <div>
            <label class="label" for="coupon_max_redemptions">
              <span class="label-text">Max redemptions (optional)</span>
            </label>
            <input
              type="number"
              id="coupon_max_redemptions"
              name="coupon[max_redemptions]"
              min="1"
              class="input input-bordered w-full"
              data-test="coupon-max-redemptions-input"
            />
          </div>

          <div class="flex gap-2 mt-4">
            <button type="submit" class="btn btn-primary" data-test="coupon-save-btn">
              Create coupon
            </button>
            <button type="button" phx-click="cancel_form" class="btn btn-ghost">Cancel</button>
          </div>
        </.form>
      </div>

      <%!-- Coupons list --%>
      <div
        :if={@coupons == [] && !@show_form}
        class="text-center py-12 text-base-content/60"
        data-test="coupons-empty"
      >
        <p>No coupons yet.</p>
      </div>

      <div :if={@coupons != []} class="space-y-3" data-test="coupons-list">
        <div
          :for={coupon <- @coupons}
          class={[
            "rounded-lg border p-4 flex items-center justify-between",
            if(!coupon.active, do: "opacity-60 border-base-300", else: "border-base-300")
          ]}
          data-test={"coupon-row-#{coupon.id}"}
        >
          <div>
            <div class="flex items-center gap-2">
              <code class="font-bold">{coupon.code}</code>
              <span :if={!coupon.active} class="badge badge-sm badge-ghost">Inactive</span>
            </div>
            <p class="text-sm text-base-content/70 mt-1">
              {format_discount(coupon)} &middot; {coupon.duration}
              <span :if={coupon.max_redemptions}>&middot; max {coupon.max_redemptions} uses</span>
            </p>
          </div>

          <div class="flex gap-2">
            <button
              :if={coupon.active}
              phx-click="deactivate_coupon"
              phx-value-id={coupon.id}
              class="btn btn-sm btn-ghost text-warning"
              data-test={"deactivate-coupon-#{coupon.id}"}
            >
              Deactivate
            </button>
          </div>
        </div>
      </div>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  defp format_discount(%{percent_off: pct}) when not is_nil(pct), do: "#{pct}% off"

  defp format_discount(%{amount_off: amt, currency: cur}) when not is_nil(amt) do
    "$#{div(amt, 100)}.#{String.pad_leading(Integer.to_string(rem(amt, 100)), 2, "0")} off #{String.upcase(cur || "usd")}"
  end

  defp format_discount(_), do: ""
end
