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
