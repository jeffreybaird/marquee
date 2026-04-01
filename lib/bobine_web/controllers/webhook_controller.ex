defmodule BobineWeb.WebhookController do
  use BobineWeb, :controller

  require Logger

  @doc """
  Receives Mux webhook events. Validates signature and enqueues processing.
  """
  def mux(conn, _params) do
    raw_body = Process.get(:raw_body) || ""

    with {:ok, payload} <- verify_mux_signature(raw_body, conn),
         {:ok, _job} <- enqueue_mux_webhook(payload) do
      send_resp(conn, 200, "ok")
    else
      {:error, :invalid_signature} ->
        Logger.warning("Invalid Mux webhook signature")
        send_resp(conn, 400, "invalid signature")

      {:error, reason} ->
        Logger.error(
          "Mux webhook error reason=#{inspect(reason, pretty: true, limit: :infinity)} " <>
            "request_path=#{conn.request_path}"
        )

        send_resp(conn, 500, "error")
    end
  end

  @doc """
  Receives Stripe webhook events. Validates signature and enqueues processing.
  """
  def stripe(conn, _params) do
    send_resp(conn, 200, "ok")
  end

  defp verify_mux_signature(raw_body, conn) do
    secret = Application.get_env(:bobine, :mux_webhook_secret)

    if secret do
      header = Plug.Conn.get_req_header(conn, "mux-signature") |> List.first()

      if header do
        case Mux.Webhooks.verify_header(raw_body, header, secret) do
          :ok ->
            {:ok, Jason.decode!(raw_body)}

          {:error, reason} ->
            Logger.warning("Mux signature verification failed",
              reason: inspect(reason),
              header: String.slice(header || "", 0, 50)
            )

            {:error, :invalid_signature}
        end
      else
        Logger.warning("No Mux-Signature header present")
        {:error, :invalid_signature}
      end
    else
      Logger.error(
        "MUX_WEBHOOK_SECRET not configured rejecting_webhook=true " <>
          "request_path=#{conn.request_path}"
      )

      {:error, :invalid_signature}
    end
  end

  defp enqueue_mux_webhook(payload) do
    %{payload: payload}
    |> Bobine.Workers.MuxWebhookProcessor.new()
    |> Oban.insert()
  end
end
