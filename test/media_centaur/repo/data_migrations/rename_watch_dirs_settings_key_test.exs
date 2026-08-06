defmodule MediaCentaur.Repo.DataMigrations.RenameWatchDirsSettingsKeyTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.RenameWatchDirsSettingsKey
  alias MediaCentaur.Settings

  @legacy_key "config:watch_dirs"
  @current_key "config:media_dirs"

  @entries [%{"id" => "abc", "dir" => "/mnt/sample", "images_dir" => nil, "name" => nil}]

  defp insert_entry(key) do
    {:ok, _} = Settings.find_or_create_entry(%{key: key, value: %{"entries" => @entries}})
  end

  defp value_for(key) do
    case Settings.get_by_key(key) do
      %{value: value} -> value
      _ -> nil
    end
  end

  describe "rename_key/1" do
    test "renames the legacy watch_dirs settings key, preserving the value" do
      insert_entry(@legacy_key)

      assert :ok = RenameWatchDirsSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"entries" => @entries}
      assert value_for(@legacy_key) == nil
    end

    test "is idempotent — a second run leaves the renamed row untouched" do
      insert_entry(@legacy_key)

      assert :ok = RenameWatchDirsSettingsKey.rename_key(Repo)
      assert :ok = RenameWatchDirsSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"entries" => @entries}
      assert value_for(@legacy_key) == nil
    end

    test "no-op when no legacy key exists" do
      assert :ok = RenameWatchDirsSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == nil
      assert value_for(@legacy_key) == nil
    end

    test "keeps the current key and drops the legacy one when both exist" do
      insert_entry(@legacy_key)

      current_entries = [%{"id" => "def", "dir" => "/mnt/newer", "images_dir" => nil, "name" => nil}]

      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: @current_key,
          value: %{"entries" => current_entries}
        })

      assert :ok = RenameWatchDirsSettingsKey.rename_key(Repo)

      assert value_for(@current_key) == %{"entries" => current_entries}
      assert value_for(@legacy_key) == nil
    end
  end
end
