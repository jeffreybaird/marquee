defmodule Bobine.Billing.StripeClient do
  @moduledoc """
  Production Stripe API client with OpenTelemetry instrumentation.

  Every Stripe API call produces a span with the operation name, HTTP status,
  idempotency key, and latency.
  """

  @behaviour Bobine.Billing.StripeClientBehaviour

  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def create_product(params) do
    traced_call("create_product", fn ->
      Stripe.Product.create(params)
    end)
  end

  @impl true
  def create_price(params) do
    traced_call("create_price", fn ->
      Stripe.Price.create(params)
    end)
  end

  @impl true
  def update_product(product_id, params) do
    traced_call("update_product", fn ->
      Stripe.Product.update(product_id, params)
    end)
  end

  @impl true
  def deactivate_price(price_id) do
    traced_call("deactivate_price", fn ->
      Stripe.Price.update(price_id, %{active: false})
    end)
  end

  @impl true
  def create_customer(params) do
    traced_call("create_customer", fn ->
      Stripe.Customer.create(params)
    end)
  end

  @impl true
  def create_subscription(customer_id, price_id) do
    key = Bobine.Idempotency.key("create_subscription", customer_id, price_id)

    traced_call("create_subscription", fn ->
      Tracer.set_attribute("stripe.idempotency_key", key)

      Stripe.Subscription.create(%{
        customer: customer_id,
        items: [%{price: price_id}]
      })
    end)
  end

  @impl true
  def cancel_subscription(subscription_id) do
    traced_call("cancel_subscription", fn ->
      Stripe.Subscription.update(subscription_id, %{cancel_at_period_end: true})
    end)
  end

  @impl true
  def create_checkout_session(params, opts \\ []) do
    traced_call("create_checkout_session", fn ->
      Stripe.Checkout.Session.create(params, opts)
    end)
  end

  @impl true
  def create_billing_portal_session(customer_id, return_url) do
    traced_call("create_billing_portal_session", fn ->
      Stripe.BillingPortal.Session.create(%{
        customer: customer_id,
        return_url: return_url
      })
    end)
  end

  @impl true
  def retrieve_subscription(subscription_id) do
    traced_call("retrieve_subscription", fn ->
      Stripe.Subscription.retrieve(subscription_id)
    end)
  end

  # ── Connected account operations (Stripe Connect) ──────────────────────

  @impl true
  def create_connect_account(params) do
    traced_call("create_connect_account", fn ->
      Stripe.Account.create(params)
    end)
  end

  @impl true
  def create_connect_account_link(account_id, params) do
    traced_call("create_connect_account_link", fn ->
      Stripe.AccountLink.create(%{
        account: account_id,
        type: :account_onboarding,
        return_url: params[:return_url] || params["return_url"],
        refresh_url: params[:refresh_url] || params["refresh_url"]
      })
    end)
  end

  @impl true
  def get_connect_account(account_id) do
    traced_call("get_connect_account", fn ->
      Stripe.Account.retrieve(account_id)
    end)
  end

  @impl true
  def create_connected_product(params, opts) do
    traced_call("create_connected_product", fn ->
      Tracer.set_attribute("stripe.connect_account", Keyword.get(opts, :connect_account))
      Stripe.Product.create(params, opts)
    end)
  end

  @impl true
  def create_connected_price(params, opts) do
    traced_call("create_connected_price", fn ->
      Tracer.set_attribute("stripe.connect_account", Keyword.get(opts, :connect_account))
      Stripe.Price.create(params, opts)
    end)
  end

  @impl true
  def deactivate_connected_price(price_id, opts) do
    traced_call("deactivate_connected_price", fn ->
      Tracer.set_attribute("stripe.connect_account", Keyword.get(opts, :connect_account))
      Stripe.Price.update(price_id, %{active: false}, opts)
    end)
  end

  @impl true
  def create_connected_coupon(params, opts) do
    traced_call("create_connected_coupon", fn ->
      Tracer.set_attribute("stripe.connect_account", Keyword.get(opts, :connect_account))
      Stripe.Coupon.create(params, opts)
    end)
  end

  @impl true
  def deactivate_connected_coupon(coupon_id, opts) do
    traced_call("deactivate_connected_coupon", fn ->
      Tracer.set_attribute("stripe.connect_account", Keyword.get(opts, :connect_account))
      Stripe.Coupon.update(coupon_id, %{metadata: %{"deactivated" => "true"}}, opts)
    end)
  end

  @impl true
  def create_connected_promotion_code(params, opts) do
    traced_call("create_connected_promotion_code", fn ->
      Tracer.set_attribute("stripe.connect_account", Keyword.get(opts, :connect_account))
      Stripe.PromotionCode.create(params, opts)
    end)
  end

  @dialyzer {:nowarn_function, create_connected_checkout_session: 1}
  @impl true
  def create_connected_checkout_session(params) do
    account_id = params[:stripe_connect_account_id] || params["stripe_connect_account_id"]
    key = Bobine.Idempotency.key("viewer_checkout", params[:organization_id], params[:viewer_id])

    traced_call("create_connected_checkout_session", fn ->
      Tracer.set_attribute("stripe.connect_account", account_id)
      Tracer.set_attribute("bobine.idempotency_key", key)

      checkout_params = %{
        mode: :subscription,
        line_items: params[:line_items],
        success_url: params[:success_url],
        cancel_url: params[:cancel_url],
        customer_email: params[:viewer_email],
        subscription_data: build_subscription_data(params),
        allow_promotion_codes: true,
        application_fee_percent: 2.0,
        metadata: %{
          "bobine_org_id" => to_string(params[:organization_id]),
          "bobine_viewer_id" => to_string(params[:viewer_id])
        }
      }

      Stripe.Checkout.Session.create(
        checkout_params,
        connect_account: account_id,
        idempotency_key: key
      )
    end)
  end

  @impl true
  def create_connected_portal_session(params, opts) do
    traced_call("create_connected_portal_session", fn ->
      Tracer.set_attribute("stripe.connect_account", Keyword.get(opts, :connect_account))
      Stripe.BillingPortal.Session.create(params, opts)
    end)
  end

  defp build_subscription_data(params) do
    base = %{
      metadata: %{
        "bobine_org_id" => to_string(params[:organization_id]),
        "bobine_viewer_id" => to_string(params[:viewer_id])
      }
    }

    if params[:trial_period_days] && params[:trial_period_days] > 0 do
      Map.put(base, :trial_period_days, params[:trial_period_days])
    else
      base
    end
  end

  defp traced_call(operation, fun) do
    Tracer.with_span "bobine.stripe.#{operation}" do
      Tracer.set_attribute("stripe.operation", operation)
      start = System.monotonic_time(:millisecond)

      result = fun.()

      duration = System.monotonic_time(:millisecond) - start
      Tracer.set_attribute("duration_ms", duration)

      case result do
        {:ok, _} = ok ->
          Tracer.set_attribute("http.status_code", 200)
          ok

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          {:error, :stripe_error, reason}
      end
    end
  end
end
