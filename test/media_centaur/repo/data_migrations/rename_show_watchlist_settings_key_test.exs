defmodule MediaCentaur.Repo.DataMigrations.RenameShowWatchlistSettingsKeyTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.RenameShowWatchlistSettingsKey
  alias MediaCentaur.Settings

  @legacy_key "show_watchlist"
  @current_key "show_discovery"

  defp insert_entry(key, enabled) do
    {:ok, _} = Settings.find_or_create_entry(%{key: key, value: %{"enabled" => enabled}})
  end

  defp value_for(key) do
    case Settings.get_by_key(key) do
      %{value: value} -> value
      _ -> nil
    end
  end

  describe "rename_key/1" do
    test "renames the legacy key, preserving the value" do
      insert_entry(@legacy_key, true)

      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"enabled" => true}
      assert value_for(@legacy_key) == nil
    end

    test "is idempotent" do
      insert_entry(@legacy_key, true)

      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)
      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"enabled" => true}
      assert value_for(@legacy_key) == nil
    end

    test "no-op when no legacy key exists" do
      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)
      assert value_for(@current_key) == nil
    end

    test "keeps the current key and drops the legacy one when both exist" do
      insert_entry(@legacy_key, true)
      insert_entry(@current_key, false)

      assert :ok = RenameShowWatchlistSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"enabled" => false}
      assert value_for(@legacy_key) == nil
    end
  end
end
