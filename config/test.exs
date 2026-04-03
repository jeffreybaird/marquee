import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :bobine, Bobine.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bobine_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :bobine, BobineWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+H1LTl9izQwD8HqXzX9He8N/JlmXvWw2I4hQyOHzgvXJCSYkXnbbjxXDjc67M3Gm",
  server: true

config :bobine, :sql_sandbox, true

config :wallaby,
  driver: Wallaby.Chrome,
  otp_app: :bobine,
  base_url: "http://localhost:4002",
  screenshot_on_failure: true,
  max_wait_time: 10_000,
  chromedriver: [
    headless: true
  ],
  window_size: [width: 1280, height: 800]

# In test we don't send emails
config :bobine, Bobine.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Run Oban jobs inline during tests
config :bobine, Oban, testing: :inline

# Mock external service clients
config :bobine, :mux_client, Bobine.Content.MockMuxClient
config :bobine, :stripe_client, Bobine.Billing.MockStripeClient

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
