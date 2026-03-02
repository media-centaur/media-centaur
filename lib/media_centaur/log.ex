defmodule MediaCentaur.Log do
  @moduledoc """
  Component-level thinking logs with runtime toggles, persistence, and zero-cost
  filtering via `:persistent_term` and an Erlang primary filter.

  ## Usage

      require MediaCentaur.Log, as: Log
      Log.info(:pipeline, "claimed 3 files")
      Log.info(:tmdb, fn -> "response: \#{inspect(data, limit: 5)}" end)

  ## IEx Helpers

      Log.enable(:pipeline)     # enable one component
      Log.disable(:pipeline)    # disable one component
      Log.solo(:pipeline)       # enable only this one
      Log.mute(:pipeline)       # enable all except this one
      Log.all()                 # enable everything
      Log.none()                # disable everything (default)
      Log.enabled()             # list currently enabled components
      Log.components()          # list all known components
      Log.status()              # {enabled, all_components}

  ## Message Format

  - Lowercase, no trailing period: `"claimed 3 files"`
  - No component prefix in message (`:component` metadata handles it)
  - Include key identifiers: file IDs, entity IDs, TMDB IDs
  - Shorten paths with `Path.basename/1` when full path adds noise
  - For decisions, log outcome AND reason: `"approved, confidence 0.92 >= 0.85 threshold"`
  - Use `fn -> ... end` for messages with expensive interpolation

  ## What NOT to Log (too noisy)

  - MPV `time-pos` property updates (every second)
  - `WatchingTracker.update` (every second)
  - Serializer per-entity calls
  - Mapper per-field transforms
  - Watcher health check when already healthy
  """

  require Logger

  @pt_key {__MODULE__, :enabled}

  @all_components [
    :watcher,
    :pipeline,
    :tmdb,
    :playback,
    :channel,
    :library
  ]

  @doc """
  Emits an info-level log tagged with the given component.
  The message can be a string or a zero-arity function for lazy evaluation.
  """
  defmacro info(component, message) do
    quote do
      require Logger
      Logger.info(unquote(message), component: unquote(component))
    end
  end

  @doc """
  Emits a warning-level log tagged with the given component.
  Warning logs always emit (the primary filter only gates info-level),
  but the component tag enables formatter attribution and Operations page UI accuracy.
  """
  defmacro warning(component, message) do
    quote do
      require Logger
      Logger.warning(unquote(message), component: unquote(component))
    end
  end

  @doc """
  Emits an error-level log tagged with the given component.
  Error logs always emit regardless of component toggle state.
  """
  defmacro error(component, message) do
    quote do
      require Logger
      Logger.error(unquote(message), component: unquote(component))
    end
  end

  # --- Erlang Primary Filter ---

  @doc """
  Erlang `:logger` primary filter. Installed once in `Application.start/2`.

  Info-level logs carrying `:component` metadata are checked against the
  enabled set in `:persistent_term`. Everything else passes through unchanged.
  """
  def filter(%{level: :info, meta: %{component: component}}, _extra) do
    if MapSet.member?(enabled_set(), component), do: :ignore, else: :stop
  end

  def filter(_event, _extra), do: :ignore

  # --- State Management ---

  @doc "Initialize from DB on application boot."
  def init do
    enabled =
      case read_setting() do
        nil -> MapSet.new()
        names -> MapSet.new(names, &String.to_existing_atom/1)
      end

    :persistent_term.put(@pt_key, enabled)
  end

  @doc "Enable a single component."
  def enable(component) when is_atom(component) do
    update_set(&MapSet.put(&1, component))
  end

  @doc "Disable a single component."
  def disable(component) when is_atom(component) do
    update_set(&MapSet.delete(&1, component))
  end

  @doc "Enable only the given component (solo mode)."
  def solo(component) when is_atom(component) do
    update_set(fn _ -> MapSet.new([component]) end)
  end

  @doc "Enable all components except the given one."
  def mute(component) when is_atom(component) do
    update_set(fn _ -> MapSet.new(@all_components) |> MapSet.delete(component) end)
  end

  @doc "Enable all components."
  def all do
    update_set(fn _ -> MapSet.new(@all_components) end)
  end

  @doc "Disable all components (default state)."
  def none do
    update_set(fn _ -> MapSet.new() end)
  end

  @doc "Returns the list of currently enabled component atoms."
  def enabled do
    enabled_set() |> Enum.sort()
  end

  @doc "Returns all known component atoms."
  def components, do: @all_components

  @doc "Returns `{enabled_list, all_components}` for display."
  def status, do: {enabled(), @all_components}

  @doc "Returns the raw MapSet of enabled components."
  def enabled_set do
    :persistent_term.get(@pt_key, MapSet.new())
  end

  # --- Framework Log Suppression ---

  @framework_modules %{
    ecto: Ecto.Adapters.SQL,
    phoenix: Phoenix.Logger,
    live_view: Phoenix.LiveView.Logger
  }

  @doc "Returns the known framework module map for the LiveView UI."
  def framework_modules, do: @framework_modules

  @doc "Initialize framework log suppression from DB on boot."
  def init_framework_levels do
    case read_framework_setting() do
      nil ->
        suppress_all_framework_modules()

      suppressed_keys ->
        keys = MapSet.new(suppressed_keys, &String.to_existing_atom/1)

        Enum.each(@framework_modules, fn {key, mod} ->
          if MapSet.member?(keys, key) do
            Logger.put_module_level(mod, :warning)
          else
            Logger.delete_module_level(mod)
          end
        end)
    end
  end

  @doc "Suppress a framework module's info/debug logs."
  def suppress_framework(key) when is_atom(key) do
    case Map.fetch(@framework_modules, key) do
      {:ok, mod} ->
        Logger.put_module_level(mod, :warning)
        update_framework_setting(&MapSet.put(&1, key))

      :error ->
        :ok
    end
  end

  @doc "Unsuppress a framework module (restore normal logging)."
  def unsuppress_framework(key) when is_atom(key) do
    case Map.fetch(@framework_modules, key) do
      {:ok, mod} ->
        Logger.delete_module_level(mod)
        update_framework_setting(&MapSet.delete(&1, key))

      :error ->
        :ok
    end
  end

  @doc "Returns the list of currently suppressed framework keys."
  def suppressed_frameworks do
    case read_framework_setting() do
      nil -> Map.keys(@framework_modules) |> Enum.sort()
      keys -> Enum.map(keys, &String.to_existing_atom/1) |> Enum.sort()
    end
  end

  # --- Private Helpers ---

  defp update_set(fun) do
    new_set = fun.(enabled_set())
    :persistent_term.put(@pt_key, new_set)
    persist_setting(new_set)
    broadcast_change()
    new_set
  end

  defp persist_setting(set) do
    names = Enum.map(set, &to_string/1)

    MediaCentaur.Library.upsert_setting!(%{
      key: "log_components",
      value: %{"enabled" => names}
    })

    :ok
  end

  defp read_setting do
    case MediaCentaur.Library.get_setting_by_key("log_components") do
      {:ok, %{value: %{"enabled" => names}}} -> names
      _ -> nil
    end
  end

  defp update_framework_setting(fun) do
    current =
      case read_framework_setting() do
        nil -> MapSet.new(Map.keys(@framework_modules))
        keys -> MapSet.new(keys, &String.to_existing_atom/1)
      end

    new_set = fun.(current)
    names = Enum.map(new_set, &to_string/1)

    MediaCentaur.Library.upsert_setting!(%{
      key: "log_framework_suppressed",
      value: %{"suppressed" => names}
    })

    broadcast_change()
    :ok
  end

  defp read_framework_setting do
    case MediaCentaur.Library.get_setting_by_key("log_framework_suppressed") do
      {:ok, %{value: %{"suppressed" => names}}} -> names
      _ -> nil
    end
  end

  defp suppress_all_framework_modules do
    Enum.each(@framework_modules, fn {_key, mod} ->
      Logger.put_module_level(mod, :warning)
    end)
  end

  defp broadcast_change do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      "logging:updates",
      :log_settings_changed
    )
  end
end
