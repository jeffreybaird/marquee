# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bobine, :scopes,
  user: [
    default: true,
    module: Bobine.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Bobine.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :bobine,
  env: config_env(),
  ecto_repos: [Bobine.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :bobine, BobineWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BobineWeb.ErrorHTML, json: BobineWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Bobine.PubSub,
  live_view: [signing_salt: "EgHZc0pV"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :bobine, Bobine.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  bobine: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  bobine: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id, :org_id, :user_id]

# Configure Oban
config :bobine, Oban,
  repo: Bobine.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10, webhooks: 5, mux: 5, stripe: 5, analytics: 3]

# OpenTelemetry
config :opentelemetry,
  resource: [
    service: [
      name: "bobine",
      version: Mix.Project.config()[:version]
    ]
  ],
  span_processor: :batch,
  traces_exporter: :otlp

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Suppress Tesla deprecation warning (comes from mux dep, not our code)
config :tesla, disable_deprecated_builder_warning: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
