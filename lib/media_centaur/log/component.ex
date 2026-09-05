defmodule MediaCentaur.Log.Component do
  @moduledoc """
  The component vocabulary — the one place that says which subsystems a
  log line can be tagged with, and which context logs as which.

  ## Why this module exists

  A component tag answers one question for the reader of the Console
  drawer: *which part of the app said this?* Before this module the answer
  was spread across four hand-maintained copies — `Console.View`'s
  `@known_components`, its `@app_components`, its chip-class map, and
  `Console.Entry`'s crash-frame table — and they disagreed. `:http` was
  added to the chip row but not to the app group, so it grouped nowhere;
  five tags that code actually emitted (`:review`, `:settings`, `:apps`,
  `:retention`, `:integration_health`) were in no list at all, so a reader
  could not filter for them; and `MediaCentaur.SelfUpdate` crashes were
  attributed to `:self_update` while every deliberate SelfUpdate log said
  `:system`.

  Everything now derives from the two tables below: the chip row, the
  grouping, the chip classes, the crash-frame attribution, and Credo
  **MC0033**, which holds a `Log.*` call's tag to its context's component.

  ## The two tables

  `@components` is the vocabulary: an ordered list of
  `{component, layer, chip_class}`. Order is chip-row display order.

  `@context_components` maps an **owning context** — the directory under
  `lib/media_centaur/`, or the context's root module file — to the
  component its code logs as. The mapping is deliberately many-to-one:
  `downloads`, `search` and `release_tracking` all log as `:acquisition`
  because getting a release is one subsystem to a reader, whatever the
  module tree says. A context absent from the table has no required
  component; MC0033 leaves it alone.

  The web layer is exempt by design. A LiveView logs about the domain it
  displays, not about itself — `IncomingLive` logging `:acquisition` is
  correct, and there is no useful `:web` component.
  """

  @fallback_chip_class "chip-system"

  # {component, layer, chip class}. Order is chip-row display order.
  @components [
    {:watcher, :app, "chip-watcher"},
    {:pipeline, :app, "chip-pipeline"},
    {:review, :app, "chip-review"},
    {:tmdb, :app, "chip-tmdb"},
    {:http, :app, "chip-http"},
    {:library, :app, "chip-library"},
    {:playback, :app, "chip-playback"},
    {:acquisition, :app, "chip-acquisition"},
    {:apps, :app, "chip-apps"},
    {:nostr, :app, "chip-nostr"},
    {:social, :app, "chip-social"},
    {:settings, :app, "chip-settings"},
    {:system, :app, "chip-system"},
    {:phoenix, :framework, "chip-phoenix"},
    {:ecto, :framework, "chip-ecto"},
    {:live_view, :framework, "chip-live_view"}
  ]

  @context_components %{
    # Acquisition — finding, grabbing and tracking a release is one
    # subsystem to a reader, across four module trees.
    "acquisition" => :acquisition,
    "downloads" => :acquisition,
    "search" => :acquisition,
    "release_tracking" => :acquisition,
    "pursuits" => :acquisition,
    # Ingest.
    "pipeline" => :pipeline,
    "discovery" => :pipeline,
    "reconciliation" => :pipeline,
    "review" => :review,
    "watcher" => :watcher,
    # Metadata and artwork both come from TMDB.
    "tmdb" => :tmdb,
    "tmdb_artwork" => :tmdb,
    "http_client" => :http,
    # Library data and its lifecycle. Retention deletes library rows;
    # maintenance repairs them.
    "library" => :library,
    "boot_heal" => :library,
    "maintenance" => :library,
    "retention" => :library,
    "subtitles" => :library,
    # Playback, and the record playback leaves behind.
    "playback" => :playback,
    "watch_history" => :playback,
    "apps" => :apps,
    "settings" => :settings,
    # The relay socket is its own component; the roster and the
    # recommendation sync are the social graph.
    "nostr" => :nostr,
    "social" => :social,
    "recommendations" => :social,
    # Infrastructure the user never names. Self-update lives here too:
    # its logs have always said :system, and the crash table now agrees.
    "application" => :system,
    "console" => :system,
    "error_reports" => :system,
    "integration_health" => :system,
    "platform" => :system,
    "runtime" => :system,
    "self_update" => :system,
    "status" => :system
  }

  @all Enum.map(@components, fn {component, _layer, _class} -> component end)
  @app Enum.flat_map(@components, fn
         {component, :app, _class} -> [component]
         _ -> []
       end)
  @framework Enum.flat_map(@components, fn
               {component, :framework, _class} -> [component]
               _ -> []
             end)
  @chip_classes Map.new(@components, fn {component, _layer, class} -> {component, class} end)

  @doc "Every component atom, in chip-row display order."
  @spec all() :: [atom()]
  def all, do: @all

  @doc "App-layer components, in display order."
  @spec app() :: [atom()]
  def app, do: @app

  @doc "Framework components, in display order."
  @spec framework() :: [atom()]
  def framework, do: @framework

  @doc """
  The CSS chip class for a component. Unknown components — a tag from a
  dependency, or one added to code before this list — render as `:system`
  rather than crashing the drawer.
  """
  @spec chip_class(atom()) :: String.t()
  def chip_class(component), do: Map.get(@chip_classes, component, @fallback_chip_class)

  # Contexts whose module name is not `Macro.camelize/1` of the directory
  # (acronyms), plus the two mappings that are not context roots at all:
  # the playback controls under Settings, and the web pages, which log
  # about the domain they display.
  @module_prefix_overrides %{
    "MediaCentaur.TMDB" => :tmdb,
    "MediaCentaur.Settings.Controls" => :playback,
    "MediaCentaurWeb.Acquisition" => :acquisition,
    "MediaCentaurWeb.Incoming" => :acquisition,
    "MediaCentaurWeb.Library" => :library,
    "MediaCentaurWeb.Review" => :review
  }

  @module_prefixes @context_components
                   |> Map.new(fn {context, component} ->
                     {"MediaCentaur." <> Macro.camelize(context), component}
                   end)
                   |> Map.merge(@module_prefix_overrides)
                   |> Enum.sort_by(fn {prefix, _component} -> -String.length(prefix) end)

  @doc """
  The component a module belongs to, or `nil` for framework and dependency
  modules.

  This is the same table as `for_context/1`, read by module name instead of
  by source path — it is what attributes a **crash** (which arrives as a
  stacktrace, with no component tag) to a subsystem. Deriving both from one
  table is the point: a crash in `MediaCentaur.WatchHistory` and a
  deliberate log from it now report the same component, which they did not
  before (audit E53).

  Matching is longest-prefix on the module name, so
  `MediaCentaurWeb.IncomingLive` resolves through `MediaCentaurWeb.Incoming`
  and `MediaCentaur.Settings.Controls` beats `MediaCentaur.Settings`.
  """
  @spec for_module(atom()) :: atom() | nil
  def for_module(module) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir." <> name ->
        Enum.find_value(@module_prefixes, fn {prefix, component} ->
          if String.starts_with?(name, prefix), do: component
        end)

      _ ->
        nil
    end
  end

  @doc "The owning-context → component map."
  @spec context_components() :: %{String.t() => atom()}
  def context_components, do: @context_components

  @doc """
  The component a given context must log as, or `nil` when the context
  has no entry (MC0033 does not opine on it).
  """
  @spec for_context(String.t() | nil) :: atom() | nil
  def for_context(nil), do: nil
  def for_context(context), do: Map.get(@context_components, context)

  @doc """
  The owning context of a source path, or `nil` for the web layer and
  anything outside `lib/media_centaur/`.

  Both `lib/media_centaur/review.ex` and `lib/media_centaur/review/intake.ex`
  resolve to `"review"` — a context's root module and its tree are the
  same owner.
  """
  @spec context_for_path(String.t()) :: String.t() | nil
  def context_for_path(path) do
    case String.split(path, "lib/media_centaur/", parts: 2) do
      [_prefix, rest] -> context_from_relative(rest)
      _ -> nil
    end
  end

  defp context_from_relative(rest) do
    case String.split(rest, "/", parts: 2) do
      [file] -> String.replace_suffix(file, ".ex", "")
      [dir, _rest] -> dir
    end
  end
end
