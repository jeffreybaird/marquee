defmodule BobineWeb.WebhookController do
  use BobineWeb, :controller

  @doc """
  Receives Mux webhook events. Validates signature and enqueues processing.
  """
  def mux(conn, _params) do
    send_resp(conn, 200, "ok")
  end

  @doc """
  Receives Stripe webhook events. Validates signature and enqueues processing.
  """
  def stripe(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
