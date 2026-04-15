# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :media_centaur,
  ecto_repos: [MediaCentaur.Repo],
  generators: [timestamp_type: :utc_datetime]

config :media_centaur, MediaCentaur.Repo,
  database: Path.expand("~/.local/share/media-centaur/media_library.db")

# Configures the endpoint
config :media_centaur, MediaCentaurWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MediaCentaurWeb.ErrorHTML, json: MediaCentaurWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MediaCentaur.PubSub,
  live_view: [signing_salt: "802OLLfH"],
  secret_key_base: "QC0XH/1hm1UEMlboIygQEPtXH1iXVgOZJJZLeIrelftuxkpsNxJ4rhG/6hNeYrEP"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  media_centaur: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  media_centaur: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :media_centaur, Oban,
  engine: Oban.Engines.Lite,
  repo: MediaCentaur.Repo,
  queues: [acquisition: 5]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
