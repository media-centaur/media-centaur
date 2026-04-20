defmodule MediaCentarr.Console.View do
  @moduledoc """
  Pure helpers for rendering Console.Entry records in LiveViews.
  No Phoenix, no LiveView, no DB dependencies. Testable with async: true.
  """

  alias MediaCentarr.Console.Entry

  # Grouped for the chip row; app first, then framework.
  @known_components [
    # app
    :watcher,
    :pipeline,
    :tmdb,
    :playback,
    :library,
    :acquisition,
    :system,
    # framework
    :phoenix,
    :ecto,
    :live_view
  ]

  @app_components [:watcher, :pipeline, :tmdb, :playback, :library, :acquisition, :system]
  @framework_components [:phoenix, :ecto, :live_view]

  # Deliberate per-component mapping. The old hash-into-daisyUI-palette approach
  # produced visually inconsistent chips (e.g. :library landing on `badge-warning`
  # made routine library logs look like alerts). Each chip now has a dedicated
  # CSS class in app.css with a cohesive categorical palette.
  @component_chip_classes %{
    watcher: "chip-watcher",
    pipeline: "chip-pipeline",
    tmdb: "chip-tmdb",
    playback: "chip-playback",
    library: "chip-library",
    acquisition: "chip-acquisition",
    system: "chip-system",
    phoenix: "chip-phoenix",
    ecto: "chip-ecto",
    live_view: "chip-live_view"
  }

  @doc "All component atoms in display order — app first, then framework."
  @spec known_components() :: [atom()]
  def known_components, do: @known_components

  @doc "App-layer component atoms."
  @spec app_components() :: [atom()]
  def app_components, do: @app_components

  @doc "Framework component atoms."
  @spec framework_components() :: [atom()]
  def framework_components, do: @framework_components

  @doc """
  Formats a UTC `%DateTime{}` as `"HH:MM:SS.mmm"` in the local system timezone.
  Falls back to ISO 8601 representation if the zone shift fails.
  """
  @spec format_timestamp(DateTime.t()) :: String.t()
  def format_timestamp(%DateTime{} = datetime) do
    local =
      case DateTime.shift_zone(datetime, "localtime") do
        {:ok, shifted} -> shifted
        {:error, _} -> datetime
      end

    hour = local.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute = local.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    second = local.second |> Integer.to_string() |> String.pad_leading(2, "0")

    ms =
      local
      |> DateTime.to_time()
      |> then(fn time ->
        {microseconds, _precision} = time.microsecond
        div(microseconds, 1000)
      end)
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    "#{hour}:#{minute}:#{second}.#{ms}"
  end

  @doc """
  Returns the DaisyUI text color class for a log level.
  """
  @spec level_color(Entry.level()) :: String.t()
  def level_color(:error), do: "text-error"
  def level_color(:warning), do: "text-warning"
  def level_color(:info), do: "text-info"
  def level_color(:debug), do: "text-base-content/60"

  @doc """
  Returns a human-readable label for a component atom.
  Returns `"system"` for `nil`.
  """
  @spec component_label(atom() | nil) :: String.t()
  def component_label(nil), do: "system"
  def component_label(component), do: Atom.to_string(component)

  @doc """
  Returns the dedicated chip CSS class for a component atom (e.g. `"chip-tmdb"`).
  The class styling lives in `app.css` under the "Console chip palette" section.
  Unknown atoms and `nil` fall back to `chip-system` so rendering never breaks.
  """
  @spec component_badge_class(atom() | nil) :: String.t()
  def component_badge_class(component) do
    Map.get(@component_chip_classes, component, "chip-system")
  end

  @doc """
  Formats a single `%Entry{}` as a plain-text line for download or copy output.
  Format: `"[HH:MM:SS.mmm] [level] [component] message"`
  """
  @spec format_line(Entry.t()) :: String.t()
  def format_line(%Entry{} = entry) do
    timestamp = format_timestamp(entry.timestamp)
    level = Atom.to_string(entry.level)
    component = component_label(entry.component)
    "[#{timestamp}] [#{level}] [#{component}] #{entry.message}"
  end

  @doc """
  Formats a list of entries (newest-first) as a multi-line plain-text string.
  Reverses to chronological order, then joins with `"\\n"`.
  """
  @spec format_lines([Entry.t()]) :: String.t()
  def format_lines([]), do: ""

  def format_lines(entries) do
    entries
    |> Enum.reverse()
    |> Enum.map_join("\n", &format_line/1)
  end

  @doc """
  Returns a CSS class indicating whether a component chip is active or inactive.
  Active means the component is set to `:show` in the filter (or defaults to show).
  """
  @spec chip_state_class(MediaCentarr.Console.Filter.t(), atom()) :: String.t()
  def chip_state_class(%{components: components, default_component: default_component}, component) do
    visibility = Map.get(components, component, default_component)

    case visibility do
      :show -> "console-chip-active"
      :hide -> "console-chip-inactive"
    end
  end

  @doc """
  Returns the DaisyUI button class for a level filter button.
  Returns `"btn-active"` when the filter's level matches the given level,
  otherwise returns `""`.
  """
  @spec level_button_class(MediaCentarr.Console.Filter.t(), atom()) :: String.t()
  def level_button_class(%{level: filter_level}, level) do
    if filter_level == level, do: "btn-active", else: ""
  end

  @doc """
  Returns a lowercase string of the entry's message suitable for the
  `data-message` attribute used by client-side search filtering.
  """
  @spec entry_search_text(Entry.t()) :: String.t()
  def entry_search_text(%Entry{message: message}), do: String.downcase(message)

  @doc """
  Returns the button label for the pause/resume toggle.
  """
  @spec pause_button_label(boolean()) :: String.t()
  def pause_button_label(true), do: "resume"
  def pause_button_label(false), do: "pause"

  @doc """
  Returns `true` iff two filters are identical except for their `:search`
  field. Used by console LiveViews to skip server-side re-streaming when
  only the text-search input changed — the client-side hook handles DOM
  filtering via `data-message` attributes.
  """
  @spec only_search_query_differs?(
          MediaCentarr.Console.Filter.t(),
          MediaCentarr.Console.Filter.t()
        ) :: boolean()
  def only_search_query_differs?(filter_a, filter_b) do
    normalize = fn filter -> %{filter | search: ""} end
    filter_a.search != filter_b.search and normalize.(filter_a) == normalize.(filter_b)
  end
end
