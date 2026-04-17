defmodule MediaCentarr.Log do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Component-tagged log macros for MediaCentarr domain logs.

  ## Usage

      require MediaCentarr.Log, as: Log
      Log.info(:pipeline, "completed batch — 3 files processed")
      Log.info(:tmdb, fn -> "fetched movie tmdb:\#{id}" end)
      Log.warning(:watcher, "file event backlog: \#{count}")
      Log.error(:library, "failed to create entity: \#{inspect(reason)}")

  Log visibility is controlled in the browser via the Console (press `\\``).
  All captured entries land in `MediaCentarr.Console.Buffer` and can be
  filtered at display time by component, level, and text search.

  ## Message Format

  - Lowercase, no trailing period: `"claimed 3 files"`
  - No component prefix in message (`:component` metadata handles it)
  - Include key identifiers: file IDs, entity IDs, TMDB IDs
  - Shorten paths with `Path.basename/1` when full path adds noise
  - For decisions, log outcome AND reason: `"approved, confidence 0.92 >= 0.85 threshold"`
  - Use `fn -> ... end` for messages with expensive interpolation
  """

  @doc "Emits an info-level log tagged with the given component."
  defmacro info(component, message) do
    quote do
      require Logger
      Logger.info(unquote(message), component: unquote(component))
    end
  end

  @doc "Emits a warning-level log tagged with the given component."
  defmacro warning(component, message) do
    quote do
      require Logger
      Logger.warning(unquote(message), component: unquote(component))
    end
  end

  @doc "Emits an error-level log tagged with the given component."
  defmacro error(component, message) do
    quote do
      require Logger
      Logger.error(unquote(message), component: unquote(component))
    end
  end
end
