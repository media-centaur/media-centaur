defmodule MediaCentaur.Library.AvailabilityTest do
  # Uses `async: false` because the module writes to a module-global
  # persistent_term key. Tests that share the cache must be serialized.
  use ExUnit.Case, async: false

  alias MediaCentaur.Library.Availability

  # Helpers to poke the cache directly, bypassing the GenServer.
  defp put_cache(map), do: :persistent_term.put({Availability, :state}, map)
  defp clear_cache, do: :persistent_term.erase({Availability, :state})

  setup do
    original = :persistent_term.get({Availability, :state}, :__unset__)

    on_exit(fn ->
      case original do
        :__unset__ -> clear_cache()
        m -> put_cache(m)
      end
    end)

    :ok
  end

  describe "dir_status/0" do
    test "returns empty map when nothing cached" do
      clear_cache()
      assert Availability.dir_status() == %{}
    end

    test "returns the cached map" do
      put_cache(%{"/mnt/a" => :watching, "/mnt/b" => :unavailable})
      assert Availability.dir_status() == %{"/mnt/a" => :watching, "/mnt/b" => :unavailable}
    end
  end
end
