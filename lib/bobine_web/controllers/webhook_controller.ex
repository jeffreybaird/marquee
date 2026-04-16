defmodule BobineWeb.WebhookController do
  use BobineWeb, :controller

  require Logger

  alias Bobine.Workers.MuxWebhookProcessor
  alias Bobine.Workers.StripeWebhookProcessor

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
        Logger.error("Mux webhook error",
          reason: inspect(reason, pretty: true, limit: :infinity),
          request_path: conn.request_path
        )

        send_resp(conn, 500, "error")
    end
  end

  @doc """
  Receives Stripe webhook events. Validates signature and enqueues processing.
  """
  def stripe(conn, _params) do
    raw_body = Process.get(:raw_body) || ""

    with {:ok, event} <- verify_stripe_signature(raw_body, conn),
         {:ok, _job} <- enqueue_stripe_webhook(event) do
      send_resp(conn, 200, "ok")
    else
      {:error, :invalid_signature} ->
        Logger.warning("Invalid Stripe webhook signature")
        send_resp(conn, 400, "invalid signature")

      {:error, reason} ->
        Logger.error("Stripe webhook error",
          reason: inspect(reason),
          request_path: conn.request_path
        )

        send_resp(conn, 500, "error")
    end
  end

  defp verify_mux_signature(raw_body, conn) do
    secret = Application.get_env(:bobine, :mux_webhook_secret)
    header = req_header(conn, "mux-signature")

    case {secret, header} do
      {nil, _} ->
        Logger.error("MUX_WEBHOOK_SECRET not configured",
          rejecting_webhook: true,
          request_path: conn.request_path
        )

        {:error, :invalid_signature}

      {_, nil} ->
        Logger.warning("No Mux-Signature header present")
        {:error, :invalid_signature}

      {secret, header} ->
        verify_mux_header(raw_body, header, secret)
    end
  end

  defp verify_stripe_signature(raw_body, conn) do
    connect_account = req_header(conn, "stripe-account")
    sig_header = req_header(conn, "stripe-signature")
    secret = stripe_webhook_secret(connect_account)

    case {secret, sig_header} do
      {nil, _} ->
        decode_unsigned_stripe_event(raw_body, connect_account)

      {_, nil} ->
        Logger.warning("No Stripe-Signature header present")
        {:error, :invalid_signature}

      {secret, sig_header} ->
        verify_stripe_event(raw_body, sig_header, secret, connect_account)
    end
  end

  defp normalize_stripe_event(%{} = event) when is_struct(event) do
    event
    |> deep_destruct()
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp normalize_stripe_event(event) when is_map(event), do: event

  defp deep_destruct(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Map.new(fn {k, v} -> {k, deep_destruct(v)} end)
  end

  defp deep_destruct(%{} = map) do
    Map.new(map, fn {k, v} -> {k, deep_destruct(v)} end)
  end

  defp deep_destruct(list) when is_list(list), do: Enum.map(list, &deep_destruct/1)
  defp deep_destruct(other), do: other

  defp enqueue_mux_webhook(payload) do
    %{payload: payload}
    |> MuxWebhookProcessor.new()
    |> Oban.insert()
  end

  defp enqueue_stripe_webhook(event) do
    %{event: event, event_id: event["id"]}
    |> StripeWebhookProcessor.new()
    |> Oban.insert()
  end

  defp req_header(conn, header), do: Plug.Conn.get_req_header(conn, header) |> List.first()

  defp verify_mux_header(raw_body, header, secret) do
    case Mux.Webhooks.verify_header(raw_body, header, secret) do
      :ok ->
        {:ok, Jason.decode!(raw_body)}

      {:error, reason} ->
        Logger.warning("Mux signature verification failed",
          reason: inspect(reason),
          header: String.slice(header, 0, 50)
        )

        {:error, :invalid_signature}
    end
  end

  defp stripe_webhook_secret(nil), do: Application.get_env(:bobine, :stripe_webhook_secret)

  defp stripe_webhook_secret(_connect_account_id) do
    Application.get_env(:bobine, :stripe_connect_webhook_secret) ||
      Application.get_env(:bobine, :stripe_webhook_secret)
  end

  defp decode_unsigned_stripe_event(raw_body, connect_account) do
    # In dev/test, accept the payload without signature verification
    case Jason.decode(raw_body) do
      {:ok, event} -> {:ok, with_connect_account(event, connect_account)}
      {:error, _} -> {:error, :invalid_signature}
    end
  end

  defp verify_stripe_event(raw_body, sig_header, secret, connect_account) do
    case Stripe.Webhook.construct_event(raw_body, sig_header, secret) do
      {:ok, event} ->
        event
        |> normalize_stripe_event()
        |> with_connect_account(connect_account)
        |> then(&{:ok, &1})

      {:error, reason} ->
        Logger.warning("Stripe signature verification failed",
          reason: inspect(reason)
        )

        {:error, :invalid_signature}
    end
  end

  defp with_connect_account(event, nil), do: event

  defp with_connect_account(event, connect_account),
    do: Map.put(event, "account", connect_account)
end
