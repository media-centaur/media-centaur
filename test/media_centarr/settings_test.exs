defmodule MediaCentarr.SettingsTest do
  @moduledoc """
  Tests for the Settings bounded context — key/value entry CRUD.
  """
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Settings

  describe "create and read" do
    test "create_entry + get_by_key round-trip" do
      assert {:ok, entry} = Settings.create_entry(%{key: "test_key", value: %{"enabled" => true}})
      assert entry.key == "test_key"
      assert entry.value == %{"enabled" => true}

      assert {:ok, found} = Settings.get_by_key("test_key")
      assert found.id == entry.id
    end

    test "get_by_key returns nil for missing key" do
      assert {:ok, nil} = Settings.get_by_key("nonexistent")
    end

    test "list_entries returns all entries" do
      Settings.create_entry!(%{key: "a", value: %{}})
      Settings.create_entry!(%{key: "b", value: %{}})

      {:ok, entries} = Settings.list_entries()
      keys = Enum.sort(Enum.map(entries, & &1.key))
      assert "a" in keys
      assert "b" in keys
    end
  end

  describe "find_or_create_entry" do
    test "creates when missing" do
      assert {:ok, entry} =
               Settings.find_or_create_entry(%{key: "new_key", value: %{"x" => 1}})

      assert entry.key == "new_key"
      assert entry.value == %{"x" => 1}
    end

    test "updates when existing" do
      {:ok, original} = Settings.create_entry(%{key: "existing", value: %{"v" => 1}})

      {:ok, updated} =
        Settings.find_or_create_entry(%{key: "existing", value: %{"v" => 2}})

      assert updated.id == original.id
      assert updated.value == %{"v" => 2}
    end
  end

  describe "update_entry" do
    test "updates the value" do
      {:ok, entry} = Settings.create_entry(%{key: "updatable", value: %{"old" => true}})

      assert {:ok, updated} = Settings.update_entry(entry, %{value: %{"new" => true}})
      assert updated.value == %{"new" => true}
    end
  end

  describe "destroy_entry" do
    test "removes the entry" do
      {:ok, entry} = Settings.create_entry(%{key: "doomed", value: %{}})
      assert :ok = Settings.destroy_entry!(entry)
      assert {:ok, nil} = Settings.get_by_key("doomed")
    end
  end
end
