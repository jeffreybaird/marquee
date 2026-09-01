defmodule Marquee.Billing.StripeClientBehaviour do
  @moduledoc """
  Behaviour contract for the Stripe API client.

  All Stripe API calls go through a module implementing this behaviour.
  In production, `Marquee.Billing.StripeClient` is used. In tests, a
  `Mox`-generated mock is injected via config.
  """

  @callback create_product(map()) :: {:ok, map()} | {:error, term()}
  @callback create_price(map()) :: {:ok, map()} | {:error, term()}
  @callback update_product(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback deactivate_price(String.t()) :: {:ok, map()} | {:error, term()}
  @callback create_customer(map()) :: {:ok, map()} | {:error, term()}
  @callback create_subscription(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback cancel_subscription(String.t()) :: {:ok, map()} | {:error, term()}
  @callback create_checkout_session(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback create_billing_portal_session(String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback retrieve_subscription(String.t()) :: {:ok, map()} | {:error, term()}

  # Connected account operations (Stripe Connect — viewer subscriptions)
  @callback create_connect_account(map()) :: {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_connect_account_link(String.t(), map()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback get_connect_account(String.t()) :: {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_connected_product(map(), keyword()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_connected_price(map(), keyword()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback deactivate_connected_price(String.t(), keyword()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_connected_coupon(map(), keyword()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback deactivate_connected_coupon(String.t(), keyword()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_connected_promotion_code(map(), keyword()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_connected_checkout_session(map()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_connected_payment_checkout_session(map()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_connected_portal_session(map(), keyword()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
  @callback create_refund(String.t(), keyword()) ::
              {:ok, map()} | {:error, :stripe_error, term()}
end
