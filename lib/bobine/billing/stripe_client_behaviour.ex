defmodule Bobine.Billing.StripeClientBehaviour do
  @moduledoc """
  Behaviour contract for the Stripe API client.

  All Stripe API calls go through a module implementing this behaviour.
  In production, `Bobine.Billing.StripeClient` is used. In tests, a
  `Mox`-generated mock is injected via config.
  """

  @callback create_customer(map()) :: {:ok, map()} | {:error, term()}
  @callback create_subscription(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback cancel_subscription(String.t()) :: {:ok, map()} | {:error, term()}
  @callback create_checkout_session(map()) :: {:ok, map()} | {:error, term()}
  @callback create_billing_portal_session(String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback retrieve_subscription(String.t()) :: {:ok, map()} | {:error, term()}
end
