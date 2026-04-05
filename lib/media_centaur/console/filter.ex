defmodule MediaCentaur.Console.Filter do
  @moduledoc """
  A pure filter struct with matchers for the console log view.

  Filtering applies AND semantics across three dimensions:
  - Level floor: entry level must be >= filter level
  - Component visibility: entry component must be :show (or default_component)
  - Search: entry message must contain the search substring (case-insensitive)
  """

  alias MediaCentaur.Console.Entry

  defstruct level: :info,
            components: %{},
            default_component: :show,
            search: "",
            search_lower: ""

  @type visibility :: :show | :hide

  @type t :: %__MODULE__{
          level: Entry.level(),
          components: %{atom() => visibility()},
          default_component: visibility(),
          search: String.t(),
          search_lower: String.t()
        }

  @level_ranks %{debug: 0, info: 1, warning: 2, error: 3}

  @doc "Constructs a new filter with the given options merged over defaults."
  @spec new(keyword() | map()) :: t()
  def new(opts \\ []), do: __MODULE__ |> struct(opts) |> put_search_lower()

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
        system: :show,
        # framework (hidden by default)
        phoenix: :hide,
        ecto: :hide,
        live_view: :hide
      },
      search: ""
    }
  end

  @doc """
  Returns `true` iff the entry passes all three filter dimensions:
  level floor, component visibility, and search substring.
  """
  @spec matches?(Entry.t(), t()) :: boolean()
  def matches?(%Entry{} = entry, %__MODULE__{} = filter) do
    level_passes?(entry, filter) and
      component_passes?(entry, filter) and
      search_passes?(entry, filter)
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
  Returns a filter where only the given component is `:show`.
  All other known components are set to `:hide`. The target component is
  always written explicitly, so callers passing an atom outside the known
  list still get the expected result.
  """
  @spec solo_component(t(), atom()) :: t()
  def solo_component(%__MODULE__{} = filter, component) do
    known = MediaCentaur.Console.View.known_components()

    updated_components =
      known
      |> Enum.reduce(filter.components, fn known_component, acc ->
        Map.put(acc, known_component, :hide)
      end)
      |> Map.put(component, :show)

    %{filter | components: updated_components}
  end

  @doc """
  Returns a filter where the given component is `:hide`.
  All other known components are set to `:show`. The target component is
  always written explicitly, so callers passing an atom outside the known
  list still get the expected result.
  """
  @spec mute_component(t(), atom()) :: t()
  def mute_component(%__MODULE__{} = filter, component) do
    known = MediaCentaur.Console.View.known_components()

    updated_components =
      known
      |> Enum.reduce(filter.components, fn known_component, acc ->
        Map.put(acc, known_component, :show)
      end)
      |> Map.put(component, :hide)

    %{filter | components: updated_components}
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
      "default_component" => Atom.to_string(filter.default_component),
      "search" => filter.search
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

    search =
      case Map.get(data, "search") do
        value when is_binary(value) -> value
        _ -> default.search
      end

    components =
      case Map.get(data, "components") do
        components_map when is_map(components_map) ->
          Map.new(components_map, fn {key, value} ->
            component_atom = safe_existing_atom(key, nil)
            visibility = safe_visibility_atom(value, :show)
            {component_atom, visibility}
          end)
          |> Map.delete(nil)

        _ ->
          default.components
      end

    %__MODULE__{
      level: level,
      components: components,
      default_component: default_component,
      search: search
    }
    |> put_search_lower()
  end

  # Fallback for any non-map input (nil, string, number, list, etc.) — return
  # a default filter so Buffer.init/1 never crashes on corrupted settings.
  def from_persistable(_), do: %__MODULE__{}

  # Private helpers

  defp level_passes?(%Entry{level: entry_level}, %__MODULE__{level: floor_level}) do
    Map.get(@level_ranks, entry_level, 0) >= Map.get(@level_ranks, floor_level, 0)
  end

  defp component_passes?(%Entry{component: component}, %__MODULE__{} = filter) do
    visibility = Map.get(filter.components, component, filter.default_component)
    visibility == :show
  end

  defp search_passes?(%Entry{}, %__MODULE__{search: ""}), do: true

  defp search_passes?(%Entry{message: message}, %__MODULE__{search_lower: search_lower}) do
    String.contains?(String.downcase(message), search_lower)
  end

  # Derived cache — keeps `search_passes?/2` from paying `String.downcase/1`
  # on the filter's search term on every entry match. Always call via `new/1`
  # or `from_persistable/1`; never construct `%Filter{search: "..."}` directly
  # in production code.
  defp put_search_lower(%__MODULE__{search: search} = filter) do
    %{filter | search_lower: String.downcase(search)}
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
    try do
      case String.to_existing_atom(value) do
        :show -> :show
        :hide -> :hide
        _ -> default
      end
    rescue
      _ -> default
    end
  end

  defp safe_existing_atom(value, default) do
    try do
      String.to_existing_atom(value)
    rescue
      _ -> default
    end
  end
end
