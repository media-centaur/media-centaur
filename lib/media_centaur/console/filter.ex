defmodule MediaCentaur.Console.Filter do
  @moduledoc """
  A pure filter struct with matchers for the console log view.

  Filtering applies AND semantics across two dimensions:
  - Level floor: entry level must be >= filter level
  - Component visibility: entry component must be :show (or default_component)

  Text search is not a filter dimension: the `/console` page owns it in the
  browser, over rows already on the page, and sends it with copy and
  download (`ConsolePageLive.Logic.matching/2`).
  """

  alias MediaCentaur.Console.Entry

  defstruct level: :info,
            components: %{},
            default_component: :show

  @type visibility :: :show | :hide

  @type t :: %__MODULE__{
          level: Entry.level(),
          components: %{atom() => visibility()},
          default_component: visibility()
        }

  @level_ranks %{debug: 0, info: 1, warning: 2, error: 3}

  @doc "Constructs a new filter with the given options merged over defaults."
  @spec new(keyword() | map()) :: t()
  def new(opts \\ []), do: struct(__MODULE__, opts)

  @doc """
  Returns a filter with seeded defaults — app components visible,
  framework components hidden.
  """
  @spec new_with_defaults() :: t()
  def new_with_defaults do
    %__MODULE__{
      level: :info,
      default_component: :show,
      components: %{
        # app (visible)
        watcher: :show,
        pipeline: :show,
        tmdb: :show,
        playback: :show,
        library: :show,
        acquisition: :show,
        system: :show,
        # framework (hidden by default)
        phoenix: :hide,
        ecto: :hide,
        live_view: :hide
      }
    }
  end

  @doc """
  A filter that admits everything — every level, every component.

  The "give me the whole store" selection. Named so call sites don't restate
  `level: :debug, default_component: :show` and drift apart.
  """
  @spec all() :: t()
  def all, do: new(level: :debug, components: %{}, default_component: :show)

  @doc """
  Returns `true` iff the entry passes both filter dimensions: level floor
  and component visibility.
  """
  @spec matches?(Entry.t(), t()) :: boolean()
  def matches?(%Entry{} = entry, %__MODULE__{} = filter) do
    level_passes?(entry, filter) and component_passes?(entry, filter)
  end

  @doc "Whether `entry`'s level clears the filter's level floor."
  @spec level_passes?(Entry.t(), t()) :: boolean()
  def level_passes?(%Entry{level: entry_level}, %__MODULE__{level: floor_level}) do
    Map.get(@level_ranks, entry_level, 0) >= Map.get(@level_ranks, floor_level, 0)
  end

  @doc """
  Whether a component is visible under this filter.

  Takes the component atom rather than an `%Entry{}` so the store can select
  which rings to read before it holds any entries.
  """
  @spec component_visible?(t(), atom()) :: boolean()
  def component_visible?(%__MODULE__{} = filter, component) when is_atom(component) do
    Map.get(filter.components, component, filter.default_component) == :show
  end

  @doc "Toggles a component between :show and :hide. Unknown components default to :show before flipping."
  @spec toggle_component(t(), atom()) :: t()
  def toggle_component(%__MODULE__{} = filter, component) do
    current = Map.get(filter.components, component, filter.default_component)

    new_visibility =
      case current do
        :show -> :hide
        :hide -> :show
      end

    %{filter | components: Map.put(filter.components, component, new_visibility)}
  end

  @doc """
  Converts the filter to a JSON-safe map with all atom values as strings.
  """
  @spec to_persistable(t()) :: map()
  def to_persistable(%__MODULE__{} = filter) do
    string_components =
      Map.new(filter.components, fn {component, visibility} ->
        {Atom.to_string(component), Atom.to_string(visibility)}
      end)

    %{
      "level" => Atom.to_string(filter.level),
      "components" => string_components,
      "default_component" => Atom.to_string(filter.default_component)
    }
  end

  @doc """
  Reconstructs a `%Filter{}` from a persisted map.

  Tolerates missing keys (uses defaults), invalid atom values (uses defaults),
  and unknown keys (ignores them). Uses `String.to_existing_atom/1` inside
  try/rescue — never `String.to_atom/1` on untrusted input.
  """
  @spec from_persistable(term()) :: t()
  def from_persistable(data) when is_map(data) do
    default = %__MODULE__{}

    level = safe_level_atom(Map.get(data, "level"), default.level)

    default_component =
      safe_visibility_atom(Map.get(data, "default_component"), default.default_component)

    components =
      case Map.get(data, "components") do
        components_map when is_map(components_map) ->
          Map.delete(
            Map.new(components_map, fn {key, value} ->
              component_atom = safe_existing_atom(key, nil)
              visibility = safe_visibility_atom(value, :show)
              {component_atom, visibility}
            end),
            nil
          )

        _ ->
          default.components
      end

    %__MODULE__{
      level: level,
      components: components,
      default_component: default_component
    }
  end

  # Fallback for any non-map input (nil, string, number, list, etc.) — return
  # a default filter so Buffer.init/1 never crashes on corrupted settings.
  def from_persistable(_), do: %__MODULE__{}

  # Private helpers

  defp component_passes?(%Entry{component: component}, %__MODULE__{} = filter) do
    component_visible?(filter, component)
  end

  defp safe_level_atom(value, default) do
    valid_levels = [:debug, :info, :warning, :error]

    try do
      atom = String.to_existing_atom(value)
      if atom in valid_levels, do: atom, else: default
    rescue
      _ -> default
    end
  end

  defp safe_visibility_atom(value, default) do
    case String.to_existing_atom(value) do
      :show -> :show
      :hide -> :hide
      _ -> default
    end
  rescue
    _ -> default
  end

  defp safe_existing_atom(value, default) do
    String.to_existing_atom(value)
  rescue
    _ -> default
  end
end
