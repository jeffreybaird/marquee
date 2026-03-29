defmodule Bobine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # OpenTelemetry auto-instrumentation — must be called before supervision tree
    OpentelemetryPhoenix.setup()
    OpentelemetryEcto.setup([:bobine, :repo])
    OpentelemetryOban.setup()
    Bobine.TelemetryHandler.setup()

    children =
      [
        BobineWeb.Telemetry,
        Bobine.Repo,
        {DNSCluster, query: Application.get_env(:bobine, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Bobine.PubSub},
        {Oban, Application.fetch_env!(:bobine, Oban)},
        Bobine.Buffers.ProgressBuffer,
        Bobine.Events.AuditSubscriber,
        # Start to serve requests, typically the last entry
        BobineWeb.Endpoint
      ]
      |> maybe_exclude_audit_subscriber()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bobine.Supervisor]
    Supervisor.start_link(children, opts)
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

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BobineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
