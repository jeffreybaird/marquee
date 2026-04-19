defmodule Bobine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Bobine.Telemetry.EctoHandler

  @impl true
  def start(_type, _args) do
    if Application.get_env(:bobine, :dev_routes) do
      setup_error_file_logger()
    end

    # OpenTelemetry auto-instrumentation — must be called before supervision tree
    OpentelemetryPhoenix.setup()
    EctoHandler.setup([:bobine, :repo])
    setup_oban_telemetry()
    Bobine.TelemetryHandler.setup()

    # ETS table for ephemeral go-back state (queue advance undo within 60s)
    :ets.new(:bobine_go_back, [:named_table, :public, :set])

    children =
      [
        BobineWeb.Telemetry,
        Bobine.Repo,
        {DNSCluster, query: Application.get_env(:bobine, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Bobine.PubSub},
        Bobine.Cache,
        {Oban, Application.fetch_env!(:bobine, Oban)},
        Bobine.Buffers.ProgressBuffer,
        Bobine.Events.AuditSubscriber,
        Bobine.Catalog.HeroCacheSubscriber,
        Bobine.Branding.CacheSubscriber,
        # Start to serve requests, typically the last entry
        BobineWeb.Endpoint
      ]
      |> maybe_add_log_shipper()
      |> maybe_exclude_audit_subscriber()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bobine.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_log_shipper(children) do
    url = Application.get_env(:bobine, :grafana_loki_url)
    auth = Application.get_env(:bobine, :grafana_loki_auth)

    if url && auth do
      Bobine.LogShipper.attach_logger_handler()
      children ++ [{Bobine.LogShipper, url: url, auth: auth}]
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
      Enum.reject(children, &(&1 == Bobine.Events.AuditSubscriber))
    end
  else
    defp maybe_exclude_audit_subscriber(children), do: children
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
    BobineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
