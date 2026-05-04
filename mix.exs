defmodule MediaCentarr.MixProject do
  use Mix.Project

  def project do
    [
      app: :media_centarr,
      version: "0.37.2",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:boundary, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev,
      releases: [
        media_centarr: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent],
          cookie: "media-centarr-local",
          steps: [:assemble, :tar]
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
      mod: {MediaCentarr.Application, []},
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

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:ecto_sqlite3, "~> 0.18"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      # Included in all envs because `import PhoenixStorybook.Router` inside
      # an `if Mix.env() == :dev` block is still validated at compile time
      # (Elixir does not dead-code-eliminate import directives — both branches
      # of the resulting case expression are compiled). The router only mounts
      # the storybook routes in :dev; :test and :prod just need the module to
      # load. The bytecode footprint is small and no routes are exposed.
      {:phoenix_storybook, "~> 1.0"},
      {:ex_code_view, path: "../../ex_code_view", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:req, "~> 0.5"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:file_system, "~> 1.0"},
      {:broadway, "~> 1.1"},
      {:image, "~> 0.54"},
      {:toml, "~> 0.7"},
      {:oban, "~> 2.19"},
      {:tidewave, "~> 0.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:credo_naming, "~> 2.1", only: [:dev, :test], runtime: false},
      {:credo_envvar, "~> 0.1", only: [:dev, :test], runtime: false},
      {:credo_check_error_handling_ecto_oban, "~> 0.9", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:boundary, "~> 0.10", runtime: false}
    ]
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
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind media_centarr", "esbuild media_centarr"],
      "assets.deploy": [
        "tailwind media_centarr --minify",
        "esbuild media_centarr --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warning-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "boundaries",
        "deps.audit",
        "sobelow",
        "test.all"
      ],
      "test.all": [
        "test",
        "cmd bun test --dots assets/js/input/"
      ]
    ]
  end

  defp usage_rules do
    [
      file: "CLAUDE.md",
      usage_rules: [
        {:elixir, link: :markdown},
        {:otp, link: :markdown},
        {:ex_code_view, link: :markdown}
      ],
      skills: [
        location: ".claude/skills",
        deps: [:ex_code_view],
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
