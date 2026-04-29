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
  database: Path.expand("~/.local/share/media-centarr/media-centarr.db")

# Configures the endpoint
config :media_centarr, MediaCentarrWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MediaCentarrWeb.ErrorHTML, json: MediaCentarrWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MediaCentarr.PubSub,
  live_view: [signing_salt: "802OLLfH"]

config :media_centarr, Oban,
  engine: Oban.Engines.Lite,
  repo: MediaCentarr.Repo,
  # acquisition: Prowlarr search fans out to every configured indexer in
  # parallel, so the real concurrency is `acquisition * indexers`. With a
  # typical 6-indexer setup, 3 workers = 18 simultaneous outbound HTTP
  # requests, which a VPN-tunnelled Prowlarr can sustain. Going higher
  # caused tail latencies of 30-45s per search (most of it queueing) and
  # tripped the per-search timeout for whole-season grabs.
  # self_update: serialized because it writes to the install dir on disk.
  queues: [acquisition: 3, self_update: 1],
  plugins: [
    # Offset minute (17) so every install doesn't hit the GitHub API
    # on the hour — spreads requests across the 60s window and keeps
    # us far under the 60/h unauthenticated rate limit.
    {Oban.Plugins.Cron,
     crontab: [
       {"17 */6 * * *", MediaCentarr.SelfUpdate.CheckerJob}
     ]}
  ]

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
