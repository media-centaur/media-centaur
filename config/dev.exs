import Config

# Custom formatter that shows [level][component] for thinking logs.
config :logger, :default_formatter,
  format: {MediaCentaur.Log.Formatter, :format},
  metadata: [:component]

config :media_centaur, MediaCentaur.Repo,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# Binding to the loopback address prevents access from other machines;
# change to `ip: {0, 0, 0, 0}` to allow it. Live-reload patterns live in
# config/runtime.exs, not here (see the note at the end of this file).
config :media_centaur, MediaCentaurWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "1080")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  # Dev-only signing key. Not a secret — this value is in the public repo and
  # is only ever used locally. Real installs load SECRET_KEY_BASE from the
  # environment via config/runtime.exs.
  secret_key_base: "dev_signing_key_not_a_secret_do_not_use_in_production_xxxxxxxxxxxxxx",
  # Watch static and templates for browser reloading.
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:media_centaur, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:media_centaur, ~w(--watch)]}
  ]

# Dev default TOML path — separate from production's XDG default so
# `iex -S mix phx.server` (no `MEDIA_CENTAUR_CONFIG_OVERRIDE` set)
# picks up dev values (port 1080, dev DB) instead of the installed
# prod config (port 2160). The dev systemd unit also points at this
# same file via its explicit override env var.
config :media_centaur, :default_config_path, "~/.config/media-centaur/media-centaur-dev.toml"

# One instance per database (ADR-084). The watchers and both pipelines
# start by default here as in production; their start flags are toggled at
# runtime on the Settings page. A second instance — a measurement server, a
# simulated host, the showcase, the e2e suite — gets its own database through
# `MEDIA_CENTAUR_CONFIG_OVERRIDE`, never this one.
config :media_centaur, :environment, :dev

# Live-reload patterns live in config/runtime.exs, not here: they are
# regexes, and a compiled regex carries a per-VM reference on OTP 28+, so
# two Mix processes never evaluate this block to equal terms. Mix compares
# the evaluated compile-time config on every compile and treats that
# mismatch as "the app config changed" — a forced rebuild of every
# dependency and every module whenever the dev server and a shell compile
# alternate. See the runtime.exs block for the full account.

# Initialize plugs at runtime for faster development compilation.
config :phoenix, :plug_init_mode, :runtime
# A higher stacktrace depth during development. Avoid this in production,
# where building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup. Changing
  # this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
