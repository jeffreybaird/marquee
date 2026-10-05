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

admin_demo_enabled =
  case System.get_env("ADMIN_DEMO_ENABLED") do
    value when value in [nil, "", "false"] -> false
    "true" -> true
    _ -> raise "ADMIN_DEMO_ENABLED must be true or false"
  end

admin_demo_host = System.get_env("ADMIN_DEMO_HOST")

valid_admin_demo_host =
  is_binary(admin_demo_host) and byte_size(admin_demo_host) <= 253 and
    Enum.all?(String.split(admin_demo_host || "", "."), fn label ->
      byte_size(label) in 1..63 and Regex.match?(~r/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/, label)
    end)

if (admin_demo_enabled or admin_demo_host not in [nil, ""]) and not valid_admin_demo_host,
  do: raise("ADMIN_DEMO_HOST must be an exact lowercase hostname")

admin_demo_trusted_proxy_ip =
  case System.get_env("ADMIN_DEMO_TRUSTED_PROXY_IP") do
    value when value in [nil, ""] ->
      nil

    value ->
      case :inet.parse_strict_address(String.to_charlist(value)) do
        {:ok, address} -> address
        {:error, _} -> raise "ADMIN_DEMO_TRUSTED_PROXY_IP must be an exact IP address"
      end
  end

config :marquee, :admin_demo,
  enabled: admin_demo_enabled,
  host: admin_demo_host,
  trusted_proxy_ip: admin_demo_trusted_proxy_ip

if admin_demo_enabled, do: config(:marquee, MarqueeWeb.Endpoint, check_origin: :conn)

# Hostname routing is enabled only after its DNS and certificates are provisioned.
case System.get_env("ORG_RESOLUTION") do
  value when value in [nil, "", "query_param"] ->
    config :marquee, :org_resolution, :query_param

  "hostname" ->
    host = System.get_env("PHX_HOST", "localhost")

    pattern =
      case System.get_env("TENANT_HOST_PATTERN") do
        value when value in [nil, ""] -> "{slug}-#{host}"
        value -> value
      end

    rendered = String.replace(pattern, "{slug}", "tenant")

    unless length(String.split(pattern, "{slug}")) == 2 and
             byte_size(rendered) <= 253 and
             Enum.all?(String.split(rendered, "."), fn label ->
               byte_size(label) <= 63 and
                 Regex.match?(~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/, label)
             end) do
      raise "TENANT_HOST_PATTERN must contain one {slug} placeholder in a hostname"
    end

    config :marquee, :org_resolution, :hostname
    config :marquee, :tenant_host_pattern, pattern
    config :marquee, MarqueeWeb.Endpoint, check_origin: :conn

  _ ->
    raise "ORG_RESOLUTION must be query_param or hostname"
end

case System.get_env("TENANT_DOMAIN_PROVISIONING") do
  value when value in [nil, "", "false"] ->
    config :marquee, :tenant_domain_provisioning, enabled: false

  "true" ->
    required = fn key ->
      case System.get_env(key) do
        value when is_binary(value) and value != "" -> value
        _ -> raise "#{key} is required for managed tenant provisioning"
      end
    end

    zone = required.("TENANT_DNS_ZONE")
    target = required.("TENANT_DNS_TARGET_IPV4")
    account = required.("DNSIMPLE_ACCOUNT_ID")
    token = required.("DNSIMPLE_API_TOKEN")

    pattern =
      case System.get_env("TENANT_HOST_PATTERN") do
        value when value in [nil, ""] -> "{slug}-#{System.get_env("PHX_HOST", "localhost")}"
        value -> value
      end

    rendered = String.replace(pattern, "{slug}", "tenant")

    valid_labels? =
      Enum.all?(String.split(rendered, "."), fn label ->
        byte_size(label) <= 63 and Regex.match?(~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/, label)
      end)

    unless match?({:ok, _}, :inet.parse_ipv4_address(String.to_charlist(target))) and
             Regex.match?(~r/\A[0-9]+\z/, account) and valid_labels? and
             byte_size(rendered) <= 253 and
             length(String.split(pattern, "{slug}")) == 2 and
             String.ends_with?(rendered, "." <> zone) do
      raise "Invalid tenant DNS target, account or managed hostname namespace"
    end

    config :marquee, :tenant_domain_provisioning,
      enabled: true,
      zone: zone,
      account_id: account,
      api_token: token,
      target_ipv4: target,
      host_pattern: pattern

    config :marquee, :tenant_host_pattern, pattern
    config :marquee, MarqueeWeb.Endpoint, check_origin: :conn

  _ ->
    raise "TENANT_DOMAIN_PROVISIONING must be true or false"
end

if config_env() != :test do
  config :marquee, MarqueeWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]

  # Mux credentials — read from env vars (set via .env in dev, GitHub Actions secrets in prod)
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
  # OpenTelemetry export to the personal OTLP hub
  # (https://elixir-as-inf.diviningdad.com). Traces go through the
  # opentelemetry_exporter; logs and metrics through otlp_shipper
  # (Marquee.Otel.Export), since the Erlang SDK cannot export those over OTLP
  # yet.
  #
  # Both OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_HUB_TOKEN are required in prod:
  # Marquee.Otel.ExporterConfig raises when either is missing so a
  # misconfigured release fails loudly instead of silently dropping telemetry.
  config :opentelemetry_exporter, Marquee.Otel.ExporterConfig.settings()

  config :marquee, :otlp_export,
    endpoint: Marquee.Otel.ExporterConfig.endpoint(),
    token: Marquee.Otel.ExporterConfig.token()

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

  # Empty string (an unset deploy var written as `MAILER_FROM=`) must not
  # override the default, so guard it the same way as the API key.
  mailer_from = System.get_env("MAILER_FROM")

  config :marquee,
    mailer_from: (mailer_from not in [nil, ""] && mailer_from) || "onboarding@resend.dev"

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
