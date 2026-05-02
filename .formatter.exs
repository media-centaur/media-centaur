[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter, Quokka],
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "storybook/**/*.exs",
    "priv/*/seeds.exs"
  ],
  # `:module_directives` excluded because Quokka's alias-lifting can shadow
  # stdlib modules (e.g. lifting `MediaCentarr.Watcher.DynamicSupervisor` to
  # `DynamicSupervisor` masks the OTP module). Imports that depend on aliased
  # names also break when Quokka reorders directives. Other rewrites
  # (pipes, deprecations, single-node fixes, etc.) remain enabled.
  quokka: [exclude: [:module_directives]]
]
