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
#     PHX_SERVER=true bin/marquee start
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
  config :marquee, MarqueeWeb.Endpoint, server: true
end

if config_env() != :test do
  config :marquee, MarqueeWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]

  # Mux credentials — read from env vars (set via .env in dev, Fly secrets in prod)
  if mux_token_id = System.get_env("MUX_TOKEN_ID") do
    config :marquee,
      mux_token_id: mux_token_id,
      mux_token_secret: System.get_env("MUX_TOKEN_SECRET"),
      mux_webhook_secret: System.get_env("MUX_WEBHOOK_SECRET")
  end

  # Stripe credentials
  if stripe_secret = System.get_env("STRIPE_SECRET_KEY") do
    config :stripity_stripe, api_key: stripe_secret
  end

  if stripe_webhook_secret = System.get_env("STRIPE_WEBHOOK_SECRET") do
    config :marquee, :stripe_webhook_secret, stripe_webhook_secret
  end

  if stripe_connect_webhook_secret = System.get_env("STRIPE_CONNECT_WEBHOOK_SECRET") do
    config :marquee, :stripe_connect_webhook_secret, stripe_connect_webhook_secret
  end

  # DigitalOcean Spaces (S3-compatible) credentials. Required for image
  # uploads; absent credentials fail fast in the client so we don't ship
  # broken presigned URLs.
  if spaces_key = System.get_env("SPACES_ACCESS_KEY_ID") do
    config :ex_aws,
      access_key_id: spaces_key,
      secret_access_key: System.get_env("SPACES_SECRET_ACCESS_KEY")
  end

  # Allow env-time override of the bucket / region for staging buckets, etc.
  if spaces_bucket = System.get_env("SPACES_BUCKET") do
    config :marquee, Marquee.Storage,
      bucket: spaces_bucket,
      region: System.get_env("SPACES_REGION", "nyc3"),
      host: System.get_env("SPACES_HOST", "nyc3.digitaloceanspaces.com"),
      public_url_base:
        System.get_env(
          "SPACES_PUBLIC_URL_BASE",
          "https://#{spaces_bucket}.#{System.get_env("SPACES_HOST", "nyc3.digitaloceanspaces.com")}"
        )
  end
end

if config_env() == :prod do
  # OpenTelemetry exporter — send traces to the configured OTLP endpoint
  # (Honeycomb, Grafana Cloud, Jaeger, etc.)
  # When no endpoint is set, disable export to avoid spamming localhost:4318
  if otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
    otel_headers =
      if auth = System.get_env("OTEL_EXPORTER_OTLP_AUTH_HEADER") do
        [{"Authorization", auth}]
      else
        []
      end

    config :opentelemetry_exporter,
      otlp_protocol: :http_protobuf,
      otlp_endpoint: otel_endpoint,
      otlp_headers: otel_headers
  else
    config :opentelemetry,
      traces_exporter: :none
  end

  # Grafana Cloud Loki — ship logs directly from the app
  if loki_url = System.get_env("GRAFANA_LOKI_URL") do
    config :marquee,
      grafana_loki_url: loki_url,
      grafana_loki_auth: System.get_env("GRAFANA_LOKI_AUTH")
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :marquee, Marquee.Repo,
    url: database_url,
    # Default 5 (not Phoenix's 10): the managed Postgres tier caps usable
    # connections near ~22, and a blue/green swap runs both colors at once
    # (2 x pool) alongside Oban + the migrate runner. 5 keeps the sum well
    # under the cap; raise POOL_SIZE once on a larger DB plan.
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
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

  config :marquee, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :marquee, MarqueeWeb.Endpoint,
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
  #     config :marquee, MarqueeWeb.Endpoint,
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
  #     config :marquee, MarqueeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Transactional email via Resend. Without a key we must NOT fall back to the
  # compile-time default (Swoosh.Adapters.Local): prod disables Local's storage
  # process, so delivering through it crashes the caller (e.g. the login
  # LiveView). Log the email instead so auth degrades gracefully rather than
  # 500-ing. Set RESEND_API_KEY to actually send mail.
  resend_key = System.get_env("RESEND_API_KEY")

  if resend_key not in [nil, ""] do
    config :marquee, Marquee.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_key
  else
    config :marquee, Marquee.Mailer, adapter: Swoosh.Adapters.Logger, level: :warning
  end

  config :marquee,
    mailer_from: System.get_env("MAILER_FROM", "onboarding@resend.dev")

  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

# == push-button-deploy: database TLS ==
# Appended by ensure-db-tls.sh — managed Postgres requires TLS, and Ecto does
# not infer it from the URL. Appended last so Config merging makes this the
# Repo's effective :ssl value. When the deploy delivers the cluster CA
# (DATABASE_CA_FILE), the server certificate is fully verified; without it the
# connection is still encrypted, just not verified.
if config_env() == :prod do
  config :marquee, Marquee.Repo,
    ssl:
      (case System.get_env("DATABASE_CA_FILE") do
         nil ->
           [verify: :verify_none]

         cacertfile ->
           [
             verify: :verify_peer,
             cacertfile: cacertfile,
             depth: 3,
             customize_hostname_check: [
               match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
             ]
           ]
       end)
end
