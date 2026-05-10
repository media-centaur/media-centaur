defmodule MediaCentarr.Profile.Suites.SettingsCacheSuite do
  @moduledoc """
  Validates that `Settings.get_by_key/1` is microsecond-scale on the
  `:persistent_term` cache path and millisecond-scale on the DB
  fallback (ADR-041). The cache is the read primitive that
  `SpoilerFree.enabled?/0`, `Capabilities.tmdb_ready?/0`, and any
  other `Settings.get_by_key`-based accessor depend on; if it
  regresses, every subscriber pays.
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.Settings

  @cache_key {Settings, :entries}
  @probe_key "profile_probe_setting"

  @impl true
  def name, do: "Settings.Cache"

  @impl true
  def inputs do
    # Create the probe entry ONCE per inputs/0 evaluation (i.e. once per
    # run_suite). The find_or_create_entry write triggers a Settings
    # broadcast that the Cache.Worker observes asynchronously; we sleep
    # briefly so the resulting refresh completes before the per-input
    # setups fire. After this point neither input writes anything, so
    # the cold-fallback erase is not racing with a pending refresh.
    ensure_probe_entry()
    Process.sleep(100)

    %{
      "warm-cache" => fn -> Settings.refresh_cache() end,
      "cold-fallback" => fn -> :persistent_term.erase(@cache_key) end
    }
  end

  @impl true
  def scenarios do
    %{
      "Settings.get_by_key/1 (existing key)" => fn ->
        Settings.get_by_key(@probe_key)
      end,
      "Settings.get_by_key/1 (missing key)" => fn ->
        Settings.get_by_key("definitely_not_a_real_key")
      end
    }
  end

  defp ensure_probe_entry do
    Settings.find_or_create_entry!(%{
      key: @probe_key,
      value: %{"v" => 1}
    })
  end
end
