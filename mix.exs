defmodule MediaCentaur.MixProject do
  use Mix.Project

  def project do
    [
      app: :media_centaur,
      version: "1.32.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      # `:permanent` makes the VM halt when the OTP application stops. Outside
      # :prod Mix starts apps :temporary, so an application shutdown — the way
      # a hot full-rebuild ends (journal 2026-09-07 10:53, and the account in
      # 03f164fa) — leaves the BEAM alive with nothing served. systemd
      # sees a healthy process, Restart= never fires, and the service is down
      # invisibly. The always-on dev unit sets MIX_START_PERMANENT=1 so that
      # failure becomes a process exit its Restart=always can act on; an ad-hoc
      # `mix phx.server` keeps the lenient default.
      start_permanent: Mix.env() == :prod or System.get_env("MIX_START_PERMANENT") == "1",
      description: "Library management and playback for a personal movie and TV collection.",
      source_url: "https://github.com/media-centaur/media-centaur",
      homepage_url: "https://media-centaur.github.io/media-centaur/",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/media-centaur/media-centaur"}
      ],
      unused: unused(),
      aliases: aliases(),
      deps: deps(),
      compilers: unused_compiler() ++ [:boundary, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev,
      releases: [
        media_centaur: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent],
          cookie: "media-centaur-local",
          steps: [:assemble, :tar],
          overlays: overlays_for_target()
        ]
      ],
      usage_rules: usage_rules()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {MediaCentaur.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, "test.all": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "credo_checks"]
  defp elixirc_paths(:dev), do: ["lib", "credo_checks"]
  defp elixirc_paths(_), do: ["lib"]

  # Per-platform release overlays. `mix release` runs natively on each target
  # OS (`priv/mac_listener` is a per-platform binary so macOS tarballs can't
  # be cross-compiled from Linux), so `:os.type/0` at evaluation time is the
  # build target. Shared overlay carries `defaults/media-centaur.toml`; the
  # OS-specific overlay carries the autostart unit file + matching installer.
  #
  # Lives outside `rel/overlays/` because mix auto-prepends that directory to
  # every release's overlays — having per-platform subtrees there would
  # double-copy every file (once stripped via this list, once with the
  # `linux/`/`darwin/` prefix from the auto-include).
  defp overlays_for_target do
    shared = "rel/platforms/shared"

    per_os =
      case :os.type() do
        {:unix, :darwin} -> "rel/platforms/darwin"
        {:unix, _} -> "rel/platforms/linux"
      end

    Enum.filter([shared, per_os], &File.dir?/1)
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:sourceror, "~> 1.12", only: [:dev, :test]},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:ecto_sqlite3, "~> 0.24"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.14"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      # Dev/test only: since 1.2 the storybook renders markdown with MDEx, a
      # Rust NIF that stays out of the release. The router mounts it through
      # `Code.eval_quoted/3` so the import is never expanded in :prod.
      {:phoenix_storybook, "~> 1.3", only: [:dev, :test]},
      {:earmark_parser, "~> 1.4"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:req, "~> 0.7"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:mint_web_socket, "~> 1.0"},
      {:websock_adapter, "~> 0.5"},
      {:bitcoinex, "~> 0.3"},
      # bitcoinex 0.3.0 still requires `decimal ~> 1.0 or ~> 2.0`, and every
      # decimal < 3.0.0 carries GHSA-rhv4-8758-jx7v (unbounded exponent in
      # `Decimal.new`), which `mix deps.audit` fails on. bitcoinex touches
      # Decimal only in `LightningNetwork.Invoice` (mult/round/equal?/
      # to_integer/from_float — all unchanged in 3.x) and we never call it, so
      # we override to the patched line instead of pinning a vulnerable dep.
      {:decimal, "~> 3.0", override: true},
      {:file_system, "~> 1.0"},
      {:broadway, "~> 1.1"},
      {:image, "~> 0.72"},
      {:toml, "~> 0.7"},
      {:oban, "~> 2.24"},
      {:tidewave, "~> 0.9", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:credo_envvar, "~> 0.1", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.13", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:boundary, "~> 0.10", runtime: false},
      {:benchee, "~> 1.5", only: [:dev, :test], runtime: false},
      {:mix_unused, "~> 0.4", only: [:dev], runtime: false}
    ]
  end

  # What the `:unused` tracer must be told about, because it cannot follow a
  # call made through `apply/3` or `module.fun()` on a variable. Every entry
  # names the seam, not the symptom.
  #
  # `ignore` is the blunter of the two mechanisms and is used deliberately:
  # it drops the MFA from the call graph, which also clears whatever that
  # function calls. `@doc export: true` at the definition site silences one
  # function and does NOT clear its subtree, so it suits leaf entry points
  # (`MediaCentaur.Release`, `MediaCentaur.Diagnostics`) and not roots.
  defp unused do
    [
      ignore: [
        # Macro-generated reflection (`__schema__/2`, `__changeset__/0`,
        # `__components__/0`, `__phoenix_verify_routes__/1`) and this repo's
        # `__<verb>_for_test__` seams (ADR-026). None is hand-written.
        {:_, ~r/^__.+__\??$/, :_},
        # Supervisors start children by module name.
        {:_, :child_spec, 1},
        {:_, :start_link, :_},
        # Credo runs checks through its own runner; `credo_checks/` is
        # compiled into :dev but nothing in `lib/` calls it.
        {~r/^MediaCentaur\.Credo\./, :_, :_},
        # `MediaCentaurWeb.Live.Subscriptions` is the one door to a context
        # topic and dispatches `module.subscribe()` on a variable (house rule
        # enforced by the ContextSubscribeFacade Credo check). Arity 0 only —
        # the facade always calls with no arguments, so `subscribe/1` and
        # friends stay visible.
        {:_, ~r/^subscribe/, 0},
        # `MediaCentaurWeb.Live.SettingAware` reads each preference's polarity
        # through `context.setting_key()` / `context.enabled?()` on a variable.
        {~r/^MediaCentaur\.Settings\.Preferences\./, :_, :_},
        # `use MediaCentaurWeb, :html` dispatches `apply(__MODULE__, which, [])`,
        # so every one of these clause helpers looks uncalled.
        {MediaCentaurWeb, :_, 0},
        # Generated by `use Ecto.Repo` / `use PhoenixStorybook` — framework
        # surface we neither write nor call.
        {MediaCentaur.Repo, :_, :_},
        {MediaCentaurWeb.Storybook, :_, :_},
        # Status Activity widgets are resolved at runtime from the
        # `:health_activity_widgets` config registry by
        # `StatusLive.ActivityWidgets.render/3`. Ignored rather than declared
        # with `@doc export: true`, because only `ignore` also clears the
        # widget's own subtree (the library-overview cards it composes).
        {~r/^MediaCentaurWeb\.Components\.StatusWidgets\./, ~r/_widget$/, 1}
      ]
    ]
  end

  # Gated so the always-on dev server's compiles stay quiet: the report is
  # `MC_UNUSED=1 mix compile --force`. Moves into `precommit` once the
  # candidate list in campaigns/dead-code-detection.md is empty.
  defp unused_compiler do
    if System.get_env("MC_UNUSED") == "1", do: [:unused], else: []
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "ecto.migrate_data",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind media_centaur", "esbuild media_centaur"],
      "assets.deploy": [
        "tailwind media_centaur --minify",
        "esbuild media_centaur --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "boundaries",
        # GHSA-52mm-h59v-f3c7 is stored XSS in earmark's HTML *render* path
        # (Earmark.Transform). We never render: GuideMarkdown calls
        # Earmark.Parser.as_ast and emits HEEx (Phoenix auto-escapes), and the
        # only markdown is trusted, repo-authored guide content — no untrusted
        # input reaches it. earmark is retired with no patched version, and the
        # maintained alternative (MDEx) is a Rust NIF we keep out of the
        # release (phoenix_storybook pulls it into :dev/:test only).
        # Unreachable advisory; ignored until we replace earmark_parser.
        "deps.audit --ignore-advisory-ids GHSA-52mm-h59v-f3c7",
        "sobelow",
        "test.all"
      ],
      "test.all": [
        "test",
        # The whole tree, not a list of directories: enumerating them is how
        # assets/js/hooks/ stayed out of every test run for three months.
        "cmd bun test --dots assets/js/"
      ]
    ]
  end

  defp usage_rules do
    [
      file: "CLAUDE.md",
      usage_rules: [
        {:elixir, link: :markdown},
        {:otp, link: :markdown}
      ],
      skills: [
        location: ".claude/skills",
        build: [
          "phoenix-framework": [
            description:
              "Use this skill working with Phoenix Framework. Consult this when working with the web layer, controllers, views, liveviews etc.",
            usage_rules: [:phoenix, ~r/^phoenix_/]
          ],
          "elixir-otp": [
            description:
              "Use this skill for working with Elixir / OTP, for example working with genservers, agents, and other OTP tools.",
            usage_rules: [:otp]
          ]
        ]
      ]
    ]
  end
end
