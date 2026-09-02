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
  database: Path.expand("~/.local/share/media-centaur/media-centaur.db"),
  # SQLite is a single writer: concurrent writers don't queue, they get
  # SQLITE_BUSY once busy_timeout elapses. The 2000ms adapter default is too
  # short for our burst-ingest write paths — a folder of images landing fans
  # out many concurrent writers (Library.Inbound, image queue, review intake,
  # release tracking), and on 2026-06-08 that produced a crash storm of
  # `Exqlite.Error: Database busy` + pool queue_timeouts across seven
  # subsystems. Make writers wait for the lock instead of failing fast. Mirrors
  # the value config/test.exs already adopted after hitting the same error
  # under async-test contention. (Bounding the fan-out itself is the deeper
  # fix — see the FAN-OUT note in lib/media_centaur/library/inbound.ex.)
  busy_timeout: 10_000,
  # busy_timeout alone does NOT cover a DEFERRED transaction: it opens with a
  # read lock, then upgrades to a write lock on the first write — and SQLite
  # returns SQLITE_BUSY *immediately* on a lock upgrade (waiting would
  # deadlock), ignoring busy_timeout entirely. That is the
  # `Database busy` on an UPDATE inside Repo.transaction we saw crash
  # Progress.Worker during downloads. IMMEDIATE takes the write lock at BEGIN,
  # so a contended write transaction *waits* (up to busy_timeout) instead of
  # failing fast. Adapter-recommended for read/write workloads; with WAL
  # (the adapter default) readers still don't block.
  default_transaction_mode: :immediate

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
  # maintenance: low-priority housekeeping (retention sweep).
  queues: [acquisition: 3, self_update: 1, images: 2, maintenance: 1],
  plugins: [
    # Finished jobs (completed/cancelled/discarded) are deleted after 7 days
    # — the Lite (SQLite) engine has no built-in retention, so without this
    # plugin oban_jobs grows forever. Window kept at a week so recent job
    # history stays inspectable while bounding the table. Described on the
    # Status page via Retention.ObanPolicy, which reads this max_age.
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
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
       # Daily run of every :sweep-mode retention policy (diagnostic events,
       # pursuit/tracking event logs, resolved incidents, image queue, stale
       # staging dirs — see each context's RetentionPolicies module). Offset
       # minute so it doesn't pile onto the hour boundary.
       {"33 4 * * *", MediaCentaur.Retention.SweepJob},
       # Daily sweep that auto-resolves open :log incidents from a superseded
       # app version (they have no other recovery signal). Offset off the hour.
       {"37 4 * * *", MediaCentaur.ErrorReports.SupersededSweepJob},
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
  acquisition: MediaCentaur.Acquisition.IncidentContext,
  friends: MediaCentaur.Friends.IncidentContext
}

# Public repo the in-app reporter opens a new issue against (user posts under
# their own GitHub login). Overridable for tests/showcase.
config :media_centaur, :diagnostics_issues_repo, "media-centaur/media-centaur"

# Health-board Activity widgets (observability Phase 4 M3b). component => {module, fun}.
config :media_centaur, :health_activity_widgets, %{
  library: {MediaCentaurWeb.Components.StatusWidgets.Library, :library_widget},
  watcher: {MediaCentaurWeb.Components.StatusWidgets.Watcher, :watcher_widget},
  pipeline: {MediaCentaurWeb.Components.StatusWidgets.Pipeline, :pipeline_widget},
  tmdb: {MediaCentaurWeb.Components.StatusWidgets.Tmdb, :tmdb_widget},
  playback: {MediaCentaurWeb.Components.StatusWidgets.Playback, :playback_widget},
  acquisition: {MediaCentaurWeb.Components.StatusWidgets.Acquisition, :acquisition_widget},
  friends: {MediaCentaurWeb.Components.StatusWidgets.Friends, :friends_widget},
  self_update: {MediaCentaurWeb.Components.StatusWidgets.SelfUpdate, :self_update_widget},
  system: {MediaCentaurWeb.Components.StatusWidgets.System, :system_widget}
}

# Retention-policy providers (data-hygiene initiative). Each context that
# retains prunable data declares its policies in a PolicyProvider module;
# Retention resolves these at runtime (boundary-clean IoC, same shape as
# :diagnostics_contributors below). Order here is display order on Status.
config :media_centaur, :retention_policy_providers, [
  MediaCentaur.Retention.ObanPolicy,
  MediaCentaur.ErrorReports.RetentionPolicies,
  MediaCentaur.Acquisition.RetentionPolicies,
  MediaCentaur.ReleaseTracking.RetentionPolicies,
  MediaCentaur.Pipeline.RetentionPolicies,
  MediaCentaur.SelfUpdate.RetentionPolicies,
  MediaCentaur.Library.RetentionPolicies,
  MediaCentaur.WatchHistory.RetentionPolicies,
  MediaCentaur.TmdbArtwork.RetentionPolicies
]

# Contexts that hold TMDB artwork cache entries alive — see
# MediaCentaur.TmdbArtwork.HoldProvider. Runtime dispatch keeps the
# referencing contexts upstream of TmdbArtwork in the Boundary graph.
config :media_centaur, :tmdb_artwork_hold_providers, [
  MediaCentaur.ReleaseTracking.TmdbArtworkHolds,
  MediaCentaur.Acquisition.TmdbArtworkHolds,
  MediaCentaur.Discovery.TmdbArtworkHolds,
  MediaCentaur.Recommendations.TmdbArtworkHolds
]

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
  # Must stay ≥ 4.2: the bundled Lightning CSS minifier has to parse
  # `@container scroll-state(...)` — 4.1.x dropped the whole rule under
  # --minify, so the pinned detail block's backing never turned on in
  # releases. scripts/preflight asserts the rule survives minification.
  version: "4.3.3",
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
