defmodule Marquee.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Marquee.Telemetry.EctoHandler

  @impl true
  def start(_type, _args) do
    if Application.get_env(:marquee, :dev_routes) do
      setup_error_file_logger()
    end

    # OpenTelemetry auto-instrumentation — must be called before supervision tree
    OpentelemetryPhoenix.setup()
    EctoHandler.setup([:marquee, :repo])
    setup_oban_telemetry()
    Marquee.TelemetryHandler.setup()

    # OTLP log export to the hub, added before the endpoint. Only when the hub
    # is configured (prod with the two env vars set); dev/test leave it off.
    maybe_add_otlp_log_handler()

    # ETS table for ephemeral go-back state (queue advance undo within 60s)
    :ets.new(:marquee_go_back, [:named_table, :public, :set])

    children =
      [
        MarqueeWeb.Telemetry,
        Marquee.Repo,
        {DNSCluster, query: Application.get_env(:marquee, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Marquee.PubSub},
        Marquee.Cache,
        {Oban, Application.fetch_env!(:marquee, Oban)},
        Marquee.Buffers.ProgressBuffer,
        Marquee.Streaming.ChatRateLimiter,
        Marquee.Events.AuditSubscriber,
        Marquee.Catalog.HeroCacheSubscriber,
        Marquee.Branding.CacheSubscriber,
        Marquee.Podcasts.LifecycleSubscriber,
        # Start to serve requests, typically the last entry
        MarqueeWeb.Endpoint
      ]
      |> maybe_add_log_shipper()
      |> maybe_exclude_audit_subscriber()
      |> maybe_exclude_podcast_lifecycle_subscriber()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Marquee.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Adds the copied OtlpLogHandler when the hub is configured (set in
  # config/runtime.exs for prod). The resource matches the trace resource:
  # service.name "marquee" and the release version. Side-effecting like the
  # Loki shipper's attach; the handler owns its own (unsupervised) process.
  defp maybe_add_otlp_log_handler do
    case Application.get_env(:marquee, Marquee.OtlpLogHandler) do
      config when is_list(config) ->
        vsn = :marquee |> Application.spec(:vsn) |> to_string()

        :logger.add_handler(:otlp_logs, Marquee.OtlpLogHandler, %{
          level: :info,
          config: %{
            endpoint: Keyword.fetch!(config, :endpoint),
            token: Keyword.fetch!(config, :token),
            resource: %{"service.name" => "marquee", "service.version" => vsn},
            flush_ms: 5_000
          }
        })

      _ ->
        :ok
    end
  end

  defp maybe_add_log_shipper(children) do
    url = Application.get_env(:marquee, :grafana_loki_url)
    auth = Application.get_env(:marquee, :grafana_loki_auth)

    if url && auth do
      Marquee.LogShipper.attach_logger_handler()
      children ++ [{Marquee.LogShipper, url: url, auth: auth}]
    else
      children
    end
  end

  # In test, Oban runs inline which sets scheduled_at to nil,
  # causing OpentelemetryOban's handler to crash on DateTime.to_iso8601(nil).
  if Mix.env() == :test do
    defp setup_oban_telemetry, do: :ok
  else
    defp setup_oban_telemetry, do: OpentelemetryOban.setup()
  end

  # In test, the AuditSubscriber can't share sandbox connections reliably.
  # Tests that need it start it explicitly.
  if Mix.env() == :test do
    defp maybe_exclude_audit_subscriber(children) do
      Enum.reject(children, &(&1 == Marquee.Events.AuditSubscriber))
    end

    # Same rationale as AuditSubscriber — the lifecycle subscriber owns its
    # own process, so it can't share sandbox checkouts with the test runner.
    defp maybe_exclude_podcast_lifecycle_subscriber(children) do
      Enum.reject(children, &(&1 == Marquee.Podcasts.LifecycleSubscriber))
    end
  else
    defp maybe_exclude_audit_subscriber(children), do: children
    defp maybe_exclude_podcast_lifecycle_subscriber(children), do: children
  end

  defp setup_error_file_logger do
    log_path = Path.join(File.cwd!(), "error.log") |> String.to_charlist()

    :logger.add_handler(:error_file, :logger_std_h, %{
      level: :warning,
      config: %{file: log_path},
      formatter: Logger.default_formatter(format: "$time [$level] $message\n")
    })
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MarqueeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
