defmodule MediaCentaur.Log do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Component-tagged log macros for MediaCentaur domain logs.

  ## Usage

      require MediaCentaur.Log, as: Log
      Log.info(:pipeline, "completed batch — 3 files processed")
      Log.info(:tmdb, fn -> "fetched movie tmdb:\#{id}" end)
      Log.warning(:watcher, "file event backlog: \#{count}")
      Log.error(:library, "failed to create entity: \#{inspect(reason)}")

  Log visibility is controlled in the browser via the Console (press `\\``).
  All captured entries land in `MediaCentaur.Console.Buffer` and can be
  filtered at display time by component, level, and text search.

  ## Message Format

  - Lowercase, no trailing period: `"claimed 3 files"`
  - No component prefix in message (`:component` metadata handles it)
  - Include key identifiers: file IDs, entity IDs, TMDB IDs
  - Shorten paths with `Path.basename/1` when full path adds noise
  - For decisions, log outcome AND reason: `"approved, confidence 0.92 >= 0.85 threshold"`
  - Use `fn -> ... end` for messages with expensive interpolation

  ## Extra metadata

  Each macro accepts an optional keyword list of additional `:logger` metadata.
  The one option the diagnostics layer reads is **`mc_incident: :skip`** — it
  keeps the line in the volatile console but tells `ErrorReports.LogHandler` not
  to mint a durable `:log` incident from it (ADR-054). Use it for a warning whose
  incident a subsystem `assess/0` already owns — e.g. download-client
  connectivity failures, owned by `Downloads.IncidentContext` — so one health
  condition is one auto-resolving incident instead of a per-log-line duplicate:

      Log.warning(:acquisition, "qbittorrent sync_maindata error — \#{inspect(reason)}",
        mc_incident: :skip)
  """

  @doc "Emits a debug-level log tagged with the given component."
  defmacro debug(component, message, metadata \\ []) do
    quote do
      require Logger
      Logger.debug(unquote(message), [{:component, unquote(component)} | unquote(metadata)])
    end
  end

  @doc "Emits an info-level log tagged with the given component."
  defmacro info(component, message, metadata \\ []) do
    quote do
      require Logger
      Logger.info(unquote(message), [{:component, unquote(component)} | unquote(metadata)])
    end
  end

  @doc "Emits a warning-level log tagged with the given component."
  defmacro warning(component, message, metadata \\ []) do
    quote do
      require Logger
      Logger.warning(unquote(message), [{:component, unquote(component)} | unquote(metadata)])
    end
  end

  @doc "Emits an error-level log tagged with the given component."
  defmacro error(component, message, metadata \\ []) do
    quote do
      require Logger
      Logger.error(unquote(message), [{:component, unquote(component)} | unquote(metadata)])
    end
  end
end
