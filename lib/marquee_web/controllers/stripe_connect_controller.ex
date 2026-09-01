defmodule MarqueeWeb.StripeConnectController do
  @moduledoc """
  Handles Stripe Connect OAuth return and refresh callbacks.
  """

  use MarqueeWeb, :controller

  require Logger

  alias Marquee.Billing

  @doc """
  Called when operator returns from Stripe Connect onboarding.

  Verifies the account is fully onboarded, then stores the credentials.
  """
  def return(conn, _params) do
    org = conn.assigns.organization

    case stripe_client().get_connect_account(org.stripe_connect_account_id) do
      {:ok, %{charges_enabled: true, details_submitted: true}} ->
        case Billing.complete_connect_onboarding(org, org.stripe_connect_account_id) do
          {:ok, _org} ->
            conn
            |> put_flash(:info, "Stripe account connected successfully.")
            |> redirect(to: ~p"/admin/settings")

          {:error, _, _} ->
            conn
            |> put_flash(:error, "Something went wrong saving your Stripe account.")
            |> redirect(to: ~p"/admin/settings")
        end

      {:ok, _incomplete} ->
        case Billing.initiate_connect_onboarding(org) do
          {:ok, url} ->
            redirect(conn, external: url)

          {:error, _, _} ->
            conn
            |> put_flash(:error, "Something went wrong. Please try again.")
            |> redirect(to: ~p"/admin/settings")
        end

      {:error, :stripe_error, reason} ->
        Logger.error("Stripe Connect return failed",
          org_id: org.id,
          reason: inspect(reason)
        )

        conn
        |> put_flash(:error, "Something went wrong connecting your Stripe account.")
        |> redirect(to: ~p"/admin/settings")
    end
  end

  @doc """
  Called when the Stripe Connect onboarding link expires or needs refresh.

  Generates a new onboarding link and redirects the operator.
  """
  def refresh(conn, _params) do
    org = conn.assigns.organization

    case Billing.initiate_connect_onboarding(org) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, _, _} ->
        conn
        |> put_flash(:error, "Something went wrong. Please try again.")
        |> redirect(to: ~p"/admin/settings")
    end
  end

  defp stripe_client,
    do: Application.get_env(:marquee, :stripe_client, Marquee.Billing.StripeClient)
end
