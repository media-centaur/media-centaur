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
  media_centaur: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :media_centaur, MediaCentaur.Repo,
  database: Path.expand("~/.local/share/media-centaur/media-centaur.db")

# Configures the endpoint
config :media_centaur, MediaCentaurWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MediaCentaurWeb.ErrorHTML, json: MediaCentaurWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MediaCentaur.PubSub,
  live_view: [signing_salt: "802OLLfH"]

config :media_centaur, Oban,
  engine: Oban.Engines.Lite,
  repo: MediaCentaur.Repo,
  # acquisition: Prowlarr search fans out to every configured indexer in
  # parallel, so the real concurrency is `acquisition * indexers`. With a
  # typical 6-indexer setup, 3 workers = 18 simultaneous outbound HTTP
  # requests, which a VPN-tunnelled Prowlarr can sustain. Going higher
  # caused tail latencies of 30-45s per search (most of it queueing) and
  # tripped the per-search timeout for whole-season grabs.
  # self_update: serialized because it writes to the install dir on disk.
  # images: per-entity artwork refresh (TMDB fetch → enqueue), kept low
  # since the heavy download/resize runs in the Broadway image pipeline.
  # maintenance: low-priority housekeeping (diagnostic-event retention prune).
  queues: [acquisition: 3, self_update: 1, images: 2, maintenance: 1],
  plugins: [
    # The CheckerJob ticks at the rate-limit floor (every 15 min) but only
    # contacts GitHub when the user's configured interval has elapsed and
    # checking is enabled — see CheckerJob.due_for_check?/5. This keeps the
    # poll interval runtime-tunable without reconfiguring Oban's cron. Minute
    # offset (2) so the tick doesn't pile onto the hour boundary.
    {Oban.Plugins.Cron,
     crontab: [
       {"2-59/15 * * * *", MediaCentaur.SelfUpdate.CheckerJob},
       # Drives `Pursuits.Policy` for every active pursuit every 15 minutes.
       # Idempotent re-reads on every wake; terminal pursuits are skipped.
       {"*/15 * * * *", MediaCentaur.Acquisition.Pursuits.Watcher},
       # Daily retention prune of the durable diagnostic-event log (~30d).
       # Offset minute so it doesn't pile onto the hour boundary.
       {"33 4 * * *", MediaCentaur.ErrorReports.PruneJob},
       # Subsystem health evaluator: polls each registered assess/0 every 5
       # minutes and reconciles :subsystem incidents (duration/trend faults).
       {"*/5 * * * *", MediaCentaur.ErrorReports.EvaluatorJob}
     ]}
  ]

# Subsystem diagnostics contributors (observability campaign). Maps a component
# to its ErrorReports.IncidentContext implementation; ErrorReports resolves
# these at runtime (boundary-clean IoC). Rolled out incrementally — TMDB first.
config :media_centaur, :diagnostics_contributors, %{
  tmdb: MediaCentaur.TMDB.IncidentContext,
  self_update: MediaCentaur.SelfUpdate.IncidentContext,
  acquisition: MediaCentaur.Downloads.IncidentContext
}

# Public repo the in-app reporter opens a new issue against (user posts under
# their own GitHub login). Overridable for tests/showcase.
config :media_centaur, :diagnostics_issues_repo, "media-centaur/media-centaur"

# Health-board Activity widgets (observability Phase 4 M3b). component => {module, fun}.
config :media_centaur, :health_activity_widgets, %{
  library: {MediaCentaurWeb.ActivityWidgetComponents, :library_widget},
  watcher: {MediaCentaurWeb.ActivityWidgetComponents, :watcher_widget},
  pipeline: {MediaCentaurWeb.ActivityWidgetComponents, :pipeline_widget},
  tmdb: {MediaCentaurWeb.ActivityWidgetComponents, :tmdb_widget},
  playback: {MediaCentaurWeb.ActivityWidgetComponents, :playback_widget},
  self_update: {MediaCentaurWeb.ActivityWidgetComponents, :self_update_widget}
}

config :media_centaur,
  ecto_repos: [MediaCentaur.Repo],
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
  media_centaur: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
