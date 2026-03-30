import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/bobine start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
# In dev, auto-load .env file so credentials are available without manual export
if config_env() == :dev and File.exists?(".env") do
  for line <- File.stream!(".env"),
      line = String.trim(line),
      line != "" and not String.starts_with?(line, "#"),
      [key, value] = String.split(line, "=", parts: 2) do
    System.put_env(key, value)
  end
end

if System.get_env("PHX_SERVER") do
  config :bobine, BobineWeb.Endpoint, server: true
end

if config_env() != :test do
  config :bobine, BobineWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]

  # Mux credentials — read from env vars (set via .env in dev, Fly secrets in prod)
  if mux_token_id = System.get_env("MUX_TOKEN_ID") do
    config :bobine,
      mux_token_id: mux_token_id,
      mux_token_secret: System.get_env("MUX_TOKEN_SECRET"),
      mux_webhook_secret: System.get_env("MUX_WEBHOOK_SECRET")
  end

  # Stripe credentials
  if stripe_secret = System.get_env("STRIPE_SECRET_KEY") do
    config :stripity_stripe, api_key: stripe_secret
  end
end

if config_env() == :prod do
  # OpenTelemetry exporter — send traces to the configured OTLP endpoint
  # (Honeycomb, Grafana Cloud, Jaeger, etc.)
  # When no endpoint is set, disable export to avoid spamming localhost:4318
  if otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
    config :opentelemetry_exporter,
      otlp_protocol: :http_protobuf,
      otlp_endpoint: otel_endpoint
  else
    config :opentelemetry,
      traces_exporter: :none
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :bobine, Bobine.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :bobine, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :bobine, BobineWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :bobine, BobineWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :bobine, BobineWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Transactional email via Resend (optional — falls back to local adapter if not set)
  if resend_key = System.get_env("RESEND_API_KEY") do
    config :bobine, Bobine.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_key

    config :bobine,
      mailer_from: System.get_env("MAILER_FROM", "onboarding@resend.dev")
  end

  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
