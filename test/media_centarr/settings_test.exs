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

      entries = Settings.list_entries()
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

  describe "get_by_keys/1" do
    test "returns a map of found entries, missing keys absent" do
      {:ok, _} = Settings.create_entry(%{key: "config:foo", value: %{value: 1}})
      {:ok, _} = Settings.create_entry(%{key: "config:bar", value: %{value: 2}})

      result = Settings.get_by_keys(["config:foo", "config:bar", "config:missing"])

      assert Map.has_key?(result, "config:foo")
      assert Map.has_key?(result, "config:bar")
      refute Map.has_key?(result, "config:missing")
    end

    test "returns empty map for empty keys list" do
      assert Settings.get_by_keys([]) == %{}
    end
  end

  describe "broadcasts" do
    setup do
      Settings.subscribe()
      :ok
    end

    test "create_entry broadcasts {:setting_changed, key, value}" do
      {:ok, _} = Settings.create_entry(%{key: "broadcast_create", value: %{"x" => 1}})
      assert_receive {:setting_changed, "broadcast_create", %{"x" => 1}}
    end

    test "find_or_create_entry broadcasts on insert" do
      {:ok, _} =
        Settings.find_or_create_entry(%{key: "broadcast_foc_new", value: %{"v" => 1}})

      assert_receive {:setting_changed, "broadcast_foc_new", %{"v" => 1}}
    end

    test "find_or_create_entry broadcasts on update" do
      {:ok, _} = Settings.create_entry(%{key: "broadcast_foc_existing", value: %{"v" => 1}})
      assert_receive {:setting_changed, "broadcast_foc_existing", %{"v" => 1}}

      {:ok, _} =
        Settings.find_or_create_entry(%{key: "broadcast_foc_existing", value: %{"v" => 2}})

      assert_receive {:setting_changed, "broadcast_foc_existing", %{"v" => 2}}
    end

    test "update_entry broadcasts the new value" do
      {:ok, entry} = Settings.create_entry(%{key: "broadcast_update", value: %{"v" => 1}})
      assert_receive {:setting_changed, "broadcast_update", _}

      {:ok, _} = Settings.update_entry(entry, %{value: %{"v" => 2}})
      assert_receive {:setting_changed, "broadcast_update", %{"v" => 2}}
    end

    test "destroy_entry broadcasts a nil value to signal deletion" do
      {:ok, entry} = Settings.create_entry(%{key: "broadcast_destroy", value: %{}})
      assert_receive {:setting_changed, "broadcast_destroy", _}

      Settings.destroy_entry(entry)
      assert_receive {:setting_changed, "broadcast_destroy", nil}
    end
  end

  describe "Cache behaviour" do
    test "relevant?/1 accepts setting_changed messages" do
      assert Settings.relevant?({:setting_changed, "any_key", %{}})
      assert Settings.relevant?({:setting_changed, "any_key", nil})
      refute Settings.relevant?(:other_message)
      refute Settings.relevant?({:other_event, "key", "value"})
    end

    test "refresh_cache/0 populates :persistent_term and is idempotent" do
      # The cache is global :persistent_term — clean up on exit so we don't
      # leak the empty test-DB snapshot into later tests' Settings reads.
      on_exit(fn -> :persistent_term.erase({Settings, :entries}) end)

      Settings.create_entry!(%{key: "cache_target", value: %{"v" => 1}})

      assert :ok = Settings.refresh_cache()
      assert :ok = Settings.refresh_cache()

      assert {:ok, %{key: "cache_target", value: %{"v" => 1}}} =
               Settings.get_by_key("cache_target")
    end
  end
end
