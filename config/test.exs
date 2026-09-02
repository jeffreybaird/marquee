import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :marquee, Marquee.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "marquee_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :marquee, MarqueeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+H1LTl9izQwD8HqXzX9He8N/JlmXvWw2I4hQyOHzgvXJCSYkXnbbjxXDjc67M3Gm",
  server: true

config :marquee, :sql_sandbox, true

# Use Chrome's "none" page-load strategy for Wallaby: `visit` returns as soon as
# navigation commits instead of blocking on the window `load` event. The DOM is
# already parsed at that point and Wallaby polls for elements, so tests behave
# the same while becoming immune to any slow or unreachable sub-resource (e.g. a
# third-party script) stalling `load` and timing out every `visit`. Setting
# :capabilities replaces Wallaby's defaults wholesale, so the full map is
# required; the `--user-agent` arg must stay so Wallaby can append the
# SQL-sandbox metadata that scopes each browser session to its test connection.
config :wallaby,
  driver: Wallaby.Chrome,
  otp_app: :marquee,
  base_url: "http://localhost:4002",
  screenshot_on_failure: true,
  max_wait_time: 10_000,
  chromedriver: [
    headless: true,
    capabilities: %{
      javascriptEnabled: false,
      loadImages: false,
      version: "",
      rotatable: false,
      takesScreenshot: true,
      cssSelectorsEnabled: true,
      nativeEvents: false,
      platform: "ANY",
      unhandledPromptBehavior: "accept",
      pageLoadStrategy: "none",
      loggingPrefs: %{browser: "DEBUG"},
      chromeOptions: %{
        args: [
          "--no-sandbox",
          "window-size=1280,800",
          "--disable-gpu",
          "--headless",
          "--fullscreen",
          "--user-agent=Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36"
        ]
      }
    }
  ],
  window_size: [width: 1280, height: 800]

# In test we don't send emails
config :marquee, Marquee.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Run Oban jobs inline during tests
config :marquee, Oban, testing: :inline

# Mock external service clients
config :marquee, :mux_client, Marquee.Content.MockMuxClient
config :marquee, :stripe_client, Marquee.Billing.MockStripeClient
config :marquee, :remote_feed_client, Marquee.Podcasts.MockRemoteFeedClient

# Disable the RateLimit plug globally in tests. The suite's shared
# 127.0.0.1 counter otherwise breaches mid-run and yields flaky 429s.
# The plug's own test file opts back in via Application.put_env/3.
config :marquee, :rate_limit_disabled, true

# Route Marquee.Storage through a Mox-backed stub in tests so no real
# requests hit DigitalOcean Spaces.
config :marquee, Marquee.Storage,
  client: Marquee.Storage.MockSpacesClient,
  bucket: "marquee-test",
  region: "nyc3",
  host: "nyc3.digitaloceanspaces.com",
  public_url_base: "https://marquee-test.nyc3.digitaloceanspaces.com"

# Disable OTel in test to avoid noise
config :opentelemetry,
  traces_exporter: :none,
  span_processor: :simple

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# ProgressBuffer flushes to Repo from its own global process. A background flush
# on the 30s timer races test teardown and disconnects the shared sandbox
# connection ("client exited"), failing a random async: false test. Tests drive
# flushing explicitly via ProgressBuffer.flush/0 (sandbox-safe), so disable the
# timer here. Production keeps the default 30s interval.
config :marquee, Marquee.Buffers.ProgressBuffer, flush_interval_ms: :infinity
