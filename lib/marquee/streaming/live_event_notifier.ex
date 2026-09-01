defmodule Marquee.Streaming.LiveEventNotifier do
  @moduledoc """
  Dispatches email notification workers for live event lifecycle transitions.

  Functions in this module enqueue Oban workers; they do not send email
  synchronously. This keeps the caller's hot path free of I/O and gives
  Oban retry semantics for email delivery.
  """

  import Swoosh.Email

  alias Marquee.Mailer
  alias Marquee.Workers.NotifyCancellationWorker
  alias Marquee.Workers.NotifyLiveNowWorker

  @doc """
  Enqueues a NotifyLiveNowWorker for the given event and org.

  Exempt from doctest — dispatches an Oban job.
  """
  def send_live_now_emails(%{id: event_id, organization_id: org_id}, _org) do
    %{"live_event_id" => event_id, "organization_id" => org_id}
    |> Marquee.Otel.put_trace_context()
    |> NotifyLiveNowWorker.new()
    |> Oban.insert()
  end

  @doc """
  Enqueues a NotifyCancellationWorker for the given event and org.

  Exempt from doctest — dispatches an Oban job.
  """
  def send_cancellation_emails(%{id: event_id, organization_id: org_id}, _org) do
    %{"live_event_id" => event_id, "organization_id" => org_id}
    |> Marquee.Otel.put_trace_context()
    |> NotifyCancellationWorker.new()
    |> Oban.insert()
  end

  @doc """
  Delivers a "live now" email to a single viewer for an event.

  Exempt from doctest — sends email.
  """
  def deliver_live_now(viewer, event, org) do
    subject = "[#{org.name}] #{event.title} is live now!"
    watch_url = build_watch_url(event, org)

    body = """

    ==============================

    Hi #{viewer.display_name || viewer.email},

    #{event.title} is streaming live right now on #{org.name}!

    Join the stream now:
    #{watch_url}

    ==============================
    """

    deliver(viewer.email, subject, body)
  end

  @doc """
  Delivers an "event canceled" email to a single viewer.

  If the event is pay-per-view, includes a note about refund processing.

  Exempt from doctest — sends email.
  """
  def deliver_cancellation(viewer, event, org) do
    subject = "[#{org.name}] #{event.title} has been canceled"
    scheduled = format_datetime(event.scheduled_start_at)

    ppv_note =
      if event.access_type == "pay_per_view" do
        "\nAs this was a pay-per-view event, refunds are being processed for all ticket holders.\n"
      else
        ""
      end

    body = """

    ==============================

    Hi #{viewer.display_name || viewer.email},

    We're sorry to inform you that #{event.title}, scheduled for #{scheduled} on #{org.name}, has been canceled.
    #{ppv_note}
    We apologize for the inconvenience. We hope to see you at future events.

    ==============================
    """

    deliver(viewer.email, subject, body)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Marquee", from_address()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp from_address do
    Application.get_env(:marquee, :mailer_from, "onboarding@resend.dev")
  end

  defp build_watch_url(event, org) do
    endpoint_config = Application.get_env(:marquee, MarqueeWeb.Endpoint)[:url] || []
    base_host = Keyword.get(endpoint_config, :host, "localhost")
    port = Keyword.get(endpoint_config, :port)
    scheme = Keyword.get(endpoint_config, :scheme, "http")
    port_suffix = port_suffix(scheme, port)

    if org.custom_domain && org.custom_domain != "" do
      "#{scheme}://#{org.custom_domain}#{port_suffix}/events/#{event.slug}"
    else
      host =
        if hostname_resolution?() and not String.contains?(base_host, ".fly.dev") do
          "#{org.slug}.#{base_host}"
        else
          base_host
        end

      "#{scheme}://#{host}#{port_suffix}/events/#{event.slug}"
    end
  end

  defp hostname_resolution? do
    Application.get_env(:marquee, :org_resolution, :query_param) == :hostname
  end

  defp port_suffix(_scheme, nil), do: ""
  defp port_suffix("http", 80), do: ""
  defp port_suffix("https", 443), do: ""
  defp port_suffix(_scheme, port), do: ":#{port}"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %-d, %Y at %-I:%M %p UTC")
  end

  defp format_datetime(_), do: "the scheduled time"
end
