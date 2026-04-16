# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  media_centarr: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :media_centarr, MediaCentarr.Repo,
  database: Path.expand("~/.local/share/media-centarr/media_library.db")

# Configures the endpoint
config :media_centarr, MediaCentarrWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MediaCentarrWeb.ErrorHTML, json: MediaCentarrWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MediaCentarr.PubSub,
  live_view: [signing_salt: "802OLLfH"],
  secret_key_base: "QC0XH/1hm1UEMlboIygQEPtXH1iXVgOZJJZLeIrelftuxkpsNxJ4rhG/6hNeYrEP"

config :media_centarr, Oban,
  engine: Oban.Engines.Lite,
  repo: MediaCentarr.Repo,
  queues: [acquisition: 5]

config :media_centarr,
  ecto_repos: [MediaCentarr.Repo],
  generators: [timestamp_type: :utc_datetime]

# Redact sensitive form params from Plug.Logger output. Any param whose
# name CONTAINS one of these substrings (case-insensitive) is replaced
# with "[FILTERED]" in request logs. When adding a new sensitive config
# key, ensure its form name matches one of these substrings or extend
# this list. See decisions/architecture/ for the policy.
# Use Jason for JSON parsing in Phoenix
config :phoenix, :filter_parameters, ~w(password api_key secret token)
config :phoenix, :json_library, Jason

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  media_centarr: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
