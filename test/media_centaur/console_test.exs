defmodule MediaCentaur.ConsoleTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Console
  alias MediaCentaur.Console.Filter

  describe "read/2" do
    test "returns a list of entries" do
      assert is_list(Console.read(Filter.all(), 1_000))
    end
  end

  describe "config/0" do
    test "returns the cap and the filter" do
      config = Console.config()

      assert is_map(config)
      assert is_integer(config.cap)
      assert %Filter{} = config.filter
    end
  end

  describe "update_filter/1 + get_filter/0" do
    test "round-trip: update and read back" do
      new_filter = Filter.new(level: :error, search: "crash")
      Console.update_filter(new_filter)

      returned_filter = Console.get_filter()

      assert returned_filter.level == :error
      assert returned_filter.search == "crash"
    end
  end

  describe "clear/0" do
    test "returns :ok and leaves the buffer empty" do
      # Console.clear/0 is a pure defdelegate to Buffer.clear/0; the
      # entry-clearing behavior itself is thoroughly covered by buffer_test.exs.
      # This test verifies only that the facade delegation chain works.
      assert Console.clear() == :ok
      assert Console.read(Filter.all(), 1_000) == []
    end
  end

  describe "known_components/0" do
    test "returns the atom list from View" do
      components = Console.known_components()

      assert is_list(components)
      assert :pipeline in components
      assert :ecto in components
      assert :system in components
    end
  end

  describe "subscribe/0" do
    test "returns :ok" do
      result = Console.subscribe()

      assert result == :ok
    end
  end
end
