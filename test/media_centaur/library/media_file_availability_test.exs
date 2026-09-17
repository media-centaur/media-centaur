defmodule MediaCentaur.Library.MediaFileAvailabilityTest do
  # Uses `async: false` because the module writes to a module-global
  # persistent_term key. Tests that share the cache must be serialized.
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Library.MediaFileAvailability

  # Helpers to poke the cache directly, bypassing the GenServer.
  defp put_cache(map), do: :persistent_term.put({MediaFileAvailability, :state}, map)
  defp clear_cache, do: :persistent_term.erase({MediaFileAvailability, :state})

  describe "dir_status/0" do
    test "returns empty map when nothing cached" do
      clear_cache()
      assert MediaFileAvailability.dir_status() == %{}
    end

    test "returns the cached map" do
      put_cache(%{"/mnt/a" => :watching, "/mnt/b" => :unavailable})
      assert MediaFileAvailability.dir_status() == %{"/mnt/a" => :watching, "/mnt/b" => :unavailable}
    end
  end
end
