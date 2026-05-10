defmodule MediaCentarr.SpoilerFree do
  use Boundary, deps: [MediaCentarr.Settings]
  @behaviour MediaCentarr.Cache

  @moduledoc """
  Typed accessor for the `spoiler_free_mode` Settings entry, backed by
  a `:persistent_term` cache.

  Before the cache existed, `MediaCentarrWeb.Live.SpoilerFreeAware`
  resolved this flag via `Settings.get_by_key/1` on every LiveView
  mount — paid twice per page load (HTTP + WebSocket) for every page
  using the trait. Now reads cost a `:persistent_term.get` and the
  Cache GenServer refreshes the snapshot on the relevant
  `{:setting_changed, "spoiler_free_mode", _}` broadcast.
  """

  alias MediaCentarr.Settings

  @cache_key {__MODULE__, :enabled}
  @setting_key "spoiler_free_mode"

  @doc "The setting key in the Settings table."
  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @doc "Subscribes the caller to settings broadcasts (the cache filters by key)."
  @impl MediaCentarr.Cache
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Settings.subscribe()

  @doc "Filters PubSub messages relevant to this cache."
  @impl MediaCentarr.Cache
  def relevant?({:setting_changed, key, _value}), do: key == @setting_key
  def relevant?(_), do: false

  @doc """
  Returns the current spoiler-free mode flag. Falls back to a live
  Settings read when the cache hasn't been initialised (e.g. in tests
  that don't start the Cache child).
  """
  @spec enabled?() :: boolean()
  def enabled? do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> read_value()
      enabled -> enabled
    end
  end

  @doc """
  Recomputes the cached flag and stores it in `:persistent_term`.
  Called once at boot by the cache worker and on every relevant
  `:setting_changed` broadcast.
  """
  @impl MediaCentarr.Cache
  @spec refresh_cache() :: :ok
  def refresh_cache do
    :persistent_term.put(@cache_key, read_value())
    :ok
  end

  defp read_value do
    case Settings.get_by_key(@setting_key) do
      {:ok, %{value: %{"enabled" => enabled}}} -> enabled == true
      _ -> false
    end
  end
end
