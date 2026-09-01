defmodule MarqueeWeb.WebhookController do
  use MarqueeWeb, :controller

  require Logger

  alias Marquee.Workers.MuxWebhookProcessor
  alias Marquee.Workers.StripeWebhookProcessor

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
    secret = Application.get_env(:marquee, :mux_webhook_secret)
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
    payload
    |> mux_job_args()
    |> Marquee.Otel.put_trace_context()
    |> MuxWebhookProcessor.new()
    |> Oban.insert()
  end

  defp enqueue_stripe_webhook(event) do
    event
    |> stripe_job_args()
    |> Marquee.Otel.put_trace_context()
    |> StripeWebhookProcessor.new()
    |> Oban.insert()
  end

  # Resolve org_id from payload data. Mux passthrough carries our org_id
  # when we set it on the upload. If not present, fall back to looking
  # up the existing Video by asset id. When neither resolves, we tag the
  # job as platform-level so the audit trail is explicit.
  defp mux_job_args(payload) do
    case resolve_mux_org_id(payload) do
      nil ->
        # platform_job_reason: Mux signed webhook before the asset was
        # linked to a Marquee Video — e.g. upload.created events fire
        # before we've inserted the video record. Processor will resolve
        # org_id as soon as the asset/upload is linked.
        %{payload: payload, platform_level: true}

      org_id ->
        %{payload: payload, organization_id: org_id}
    end
  end

  defp stripe_job_args(event) do
    case resolve_stripe_org_id(event) do
      nil ->
        # platform_job_reason: Stripe event for an unknown Connect
        # account or a platform-level Marquee subscription event that
        # does not map to a single tenant. Processor routes based on
        # event type.
        %{event: event, event_id: event["id"], platform_level: true}

      org_id ->
        %{event: event, event_id: event["id"], organization_id: org_id}
    end
  end

  defp resolve_mux_org_id(payload) do
    passthrough_org_id(payload) ||
      asset_lookup_org_id(payload) ||
      upload_lookup_org_id(payload)
  end

  defp passthrough_org_id(%{"data" => %{"passthrough" => pt}}) when is_binary(pt) do
    decode_passthrough(pt)
  end

  defp passthrough_org_id(_), do: nil

  defp decode_passthrough(pt) do
    case Jason.decode(pt) do
      {:ok, %{"organization_id" => id}} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp asset_lookup_org_id(%{"data" => %{"id" => asset_id}}) when is_binary(asset_id) do
    Marquee.Content.get_organization_id_by_mux_asset_id(asset_id)
  end

  defp asset_lookup_org_id(_), do: nil

  defp upload_lookup_org_id(%{"data" => %{"upload_id" => upload_id}}) when is_binary(upload_id) do
    Marquee.Content.get_organization_id_by_mux_upload_id(upload_id)
  end

  defp upload_lookup_org_id(_), do: nil

  defp resolve_stripe_org_id(event) do
    metadata_org_id(event) || connect_account_org_id(event)
  end

  defp metadata_org_id(%{"data" => %{"object" => %{"metadata" => %{"organization_id" => id}}}})
       when is_binary(id),
       do: id

  defp metadata_org_id(_), do: nil

  defp connect_account_org_id(%{"account" => acct}) when is_binary(acct) do
    Marquee.Accounts.get_organization_id_by_stripe_connect_account_id(acct)
  end

  defp connect_account_org_id(_), do: nil

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

  defp stripe_webhook_secret(nil), do: Application.get_env(:marquee, :stripe_webhook_secret)

  defp stripe_webhook_secret(_connect_account_id) do
    Application.get_env(:marquee, :stripe_connect_webhook_secret) ||
      Application.get_env(:marquee, :stripe_webhook_secret)
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
