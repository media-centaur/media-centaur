defmodule MediaCentarrWeb.ConsoleLive.LogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Console.{Buffer, Entry, Filter}
  alias MediaCentarrWeb.ConsoleLive.Logic

  # --- Helpers ---

  defp build_entry(overrides \\ %{}) do
    defaults = %{
      id: System.unique_integer([:positive, :monotonic]),
      timestamp: ~U[2026-04-05 12:00:00.000Z],
      level: :info,
      component: :pipeline,
      message: "hello world",
      module: nil,
      metadata: %{}
    }

    Entry.new(Map.merge(defaults, overrides))
  end

  # --- initial_snapshot/0 ---

  describe "initial_snapshot/0" do
    test "returns a snapshot shape with empty entries, default cap, and default filter" do
      snapshot = Logic.initial_snapshot()

      assert snapshot.entries == []
      assert snapshot.cap == Buffer.default_cap()
      assert %Filter{} = snapshot.filter
      # Default filter has app components visible, framework hidden
      assert snapshot.filter.components[:pipeline] == :show
      assert snapshot.filter.components[:ecto] == :hide
    end
  end

  # --- should_insert_entry?/3 ---

  describe "should_insert_entry?/3" do
    setup do
      %{filter: Filter.new_with_defaults(), entry: build_entry()}
    end

    test "returns false when paused", %{filter: filter, entry: entry} do
      refute Logic.should_insert_entry?(filter, true, entry)
    end

    test "returns false when filter rejects the entry", %{filter: filter} do
      debug_entry = build_entry(%{level: :debug, component: :pipeline})
      # Default filter level is :info, so :debug is below the floor
      refute Logic.should_insert_entry?(filter, false, debug_entry)
    end

    test "returns true when not paused and filter matches", %{filter: filter, entry: entry} do
      assert Logic.should_insert_entry?(filter, false, entry)
    end

    test "returns false when entry's component is hidden" do
      filter = Filter.new_with_defaults()
      ecto_entry = build_entry(%{component: :ecto})
      refute Logic.should_insert_entry?(filter, false, ecto_entry)
    end
  end

  # --- visible_entries/2 ---

  describe "visible_entries/2" do
    test "returns empty list for empty snapshot" do
      snapshot = %{entries: []}
      assert Logic.visible_entries(snapshot, Filter.new_with_defaults()) == []
    end

    test "filters out entries that do not match the filter" do
      filter = Filter.new_with_defaults()
      keep = build_entry(%{level: :warning, component: :pipeline, message: "keep"})
      drop = build_entry(%{level: :debug, component: :pipeline, message: "drop"})

      result = Logic.visible_entries(%{entries: [keep, drop]}, filter)

      assert length(result) == 1
      assert hd(result).message == "keep"
    end

    test "preserves the order of the input entries" do
      filter = Filter.new_with_defaults()
      first = build_entry(%{message: "first"})
      second = build_entry(%{message: "second"})
      third = build_entry(%{message: "third"})

      result = Logic.visible_entries(%{entries: [first, second, third]}, filter)

      assert Enum.map(result, & &1.message) == ["first", "second", "third"]
    end
  end

  # --- format_visible_payload/2 ---

  describe "format_visible_payload/2" do
    test "returns empty string for empty list" do
      assert Logic.format_visible_payload([], Filter.new_with_defaults()) == ""
    end

    test "filters then formats the surviving entries as multi-line text" do
      filter = Filter.new_with_defaults()

      entries = [
        build_entry(%{level: :warning, message: "first"}),
        build_entry(%{level: :debug, message: "dropped"}),
        build_entry(%{level: :info, message: "second"})
      ]

      payload = Logic.format_visible_payload(entries, filter)

      assert payload =~ "first"
      assert payload =~ "second"
      refute payload =~ "dropped"
      assert String.contains?(payload, "\n")
    end
  end

  # --- download_filename/1 ---

  describe "download_filename/1" do
    test "returns a deterministic filename for a given timestamp" do
      timestamp = ~U[2026-04-05 14:23:45Z]
      assert Logic.download_filename(timestamp) == "media-centarr-2026-04-05T14-23-45.log"
    end

    test "uses UTC hours regardless of system time" do
      timestamp = ~U[2026-01-01 00:00:00Z]
      assert Logic.download_filename(timestamp) == "media-centarr-2026-01-01T00-00-00.log"
    end
  end

  # --- toggle_component/2 ---

  describe "toggle_component/2" do
    test "toggles a known component from show to hide" do
      filter = Filter.new_with_defaults()
      assert filter.components[:pipeline] == :show

      updated = Logic.toggle_component(filter, "pipeline")
      assert updated.components[:pipeline] == :hide
    end

    test "toggles a known component from hide to show" do
      filter = Filter.new_with_defaults()
      assert filter.components[:ecto] == :hide

      updated = Logic.toggle_component(filter, "ecto")
      assert updated.components[:ecto] == :show
    end

    test "falls back to :system for unknown component strings" do
      filter = Filter.new_with_defaults()
      # Unknown strings become :system via safe_to_existing_atom — :system is
      # a known component, so this toggles the :system visibility.
      updated = Logic.toggle_component(filter, "not_a_real_component_zzz")
      refute updated.components[:system] == filter.components[:system]
    end
  end

  # --- solo_component/2 ---

  describe "solo_component/2" do
    test "solos a single known component" do
      filter = Filter.new_with_defaults()
      updated = Logic.solo_component(filter, "pipeline")

      assert updated.components[:pipeline] == :show
      assert updated.components[:watcher] == :hide
      assert updated.components[:tmdb] == :hide
    end
  end

  # --- mute_component/2 ---

  describe "mute_component/2" do
    test "mutes a single known component while showing others" do
      filter = Filter.new_with_defaults()
      updated = Logic.mute_component(filter, "pipeline")

      assert updated.components[:pipeline] == :hide
      assert updated.components[:watcher] == :show
      assert updated.components[:tmdb] == :show
    end
  end

  # --- set_level/2 ---

  describe "set_level/2" do
    test "sets the filter level to a known level atom" do
      filter = Filter.new_with_defaults()
      updated = Logic.set_level(filter, "warning")
      assert updated.level == :warning
    end

    test "falls back to :system for an invalid level string" do
      # safe_to_existing_atom returns :system on failure — :system is not a
      # valid level so the filter carries a :system level after this call.
      # We intentionally don't raise here; invalid input is simply absorbed.
      filter = Filter.new_with_defaults()
      updated = Logic.set_level(filter, "nope_unknown_level")
      assert updated.level == :system
    end
  end

  # --- set_search/2 ---

  describe "set_search/2" do
    test "sets the search string on the filter" do
      filter = Filter.new_with_defaults()
      updated = Logic.set_search(filter, "needle")
      assert updated.search == "needle"
    end

    test "sets an empty search string" do
      filter = %Filter{Filter.new_with_defaults() | search: "old"}
      updated = Logic.set_search(filter, "")
      assert updated.search == ""
    end
  end

  # --- parse_buffer_size/1 ---

  describe "parse_buffer_size/1" do
    test "parses a valid integer string to {:ok, n}" do
      assert Logic.parse_buffer_size("2000") == {:ok, 2000}
    end

    test "returns :invalid for a non-numeric string" do
      assert Logic.parse_buffer_size("abc") == :invalid
    end

    test "returns :invalid for an empty string" do
      assert Logic.parse_buffer_size("") == :invalid
    end

    test "parses an integer with trailing junk by taking the numeric prefix" do
      # Preserves current Integer.parse-based semantics — the existing handler
      # accepted any string Integer.parse could decode. Documented here to
      # prevent accidental tightening.
      assert Logic.parse_buffer_size("2000abc") == {:ok, 2000}
    end
  end

  # --- entry_dom_id/1 ---

  describe "entry_dom_id/1" do
    test "returns the console-log-#{~s(id)} format" do
      entry = build_entry(%{id: 42})
      assert Logic.entry_dom_id(entry) == "console-log-42"
    end

    test "works for large integer ids" do
      entry = build_entry(%{id: 1_234_567_890})
      assert Logic.entry_dom_id(entry) == "console-log-1234567890"
    end
  end

  # --- safe_to_existing_atom/1 ---

  describe "safe_to_existing_atom/1" do
    test "converts a string that matches an existing atom" do
      # :pipeline already exists at compile time in this test module
      assert Logic.safe_to_existing_atom("pipeline") == :pipeline
    end

    test "returns :system for an unknown string" do
      assert Logic.safe_to_existing_atom("totally_unknown_atom_zzz") == :system
    end
  end
end
