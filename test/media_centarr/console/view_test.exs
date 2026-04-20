defmodule MediaCentarr.Console.ViewTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Console.Entry
  alias MediaCentarr.Console.Filter
  alias MediaCentarr.Console.View

  defp build_entry(overrides) do
    defaults = [
      id: 1,
      timestamp: ~U[2026-04-05 14:30:45.123Z],
      level: :info,
      component: :pipeline,
      message: "test message"
    ]

    Entry.new(Keyword.merge(defaults, overrides))
  end

  describe "known_components/0" do
    test "returns the full list of known component atoms" do
      components = View.known_components()

      assert :watcher in components
      assert :pipeline in components
      assert :tmdb in components
      assert :playback in components
      assert :library in components
      assert :system in components
      assert :phoenix in components
      assert :ecto in components
      assert :live_view in components
    end

    test "app components come before framework components" do
      components = View.known_components()
      app = View.app_components()
      framework = View.framework_components()

      app_indices = Enum.map(app, &Enum.find_index(components, fn c -> c == &1 end))
      framework_indices = Enum.map(framework, &Enum.find_index(components, fn c -> c == &1 end))

      assert Enum.max(app_indices) < Enum.min(framework_indices)
    end
  end

  describe "app_components/0" do
    test "returns the app component atoms" do
      assert View.app_components() == [
               :watcher,
               :pipeline,
               :tmdb,
               :playback,
               :library,
               :acquisition,
               :system
             ]
    end
  end

  describe "framework_components/0" do
    test "returns the framework component atoms" do
      assert View.framework_components() == [:phoenix, :ecto, :live_view]
    end
  end

  describe "format_timestamp/1" do
    test "formats a known UTC datetime to HH:MM:SS.mmm in local zone" do
      # Using a fixed UTC datetime — the exact output depends on the local timezone,
      # so we test the format shape rather than exact value.
      dt = ~U[2026-04-05 14:30:45.123Z]
      result = View.format_timestamp(dt)

      # Must match HH:MM:SS.mmm pattern
      assert String.match?(result, ~r/^\d{2}:\d{2}:\d{2}\.\d{3}$/)
    end

    test "zero-pads milliseconds to 3 digits" do
      # 5ms should appear as 005
      dt = ~U[2026-01-01 00:00:00.005Z]
      result = View.format_timestamp(dt)
      assert String.match?(result, ~r/^\d{2}:\d{2}:\d{2}\.\d{3}$/)
      # The last 3 chars are the millisecond portion
      ms_part = String.slice(result, -3, 3)
      assert String.length(ms_part) == 3
      assert String.match?(ms_part, ~r/^\d{3}$/)
    end

    test "produces consistent length output" do
      dt = ~U[2026-04-05 14:30:45.123Z]
      result = View.format_timestamp(dt)
      # HH:MM:SS.mmm = 12 characters
      assert String.length(result) == 12
    end
  end

  describe "level_color/1" do
    test ":error returns text-error" do
      assert View.level_color(:error) == "text-error"
    end

    test ":warning returns text-warning" do
      assert View.level_color(:warning) == "text-warning"
    end

    test ":info returns text-info" do
      assert View.level_color(:info) == "text-info"
    end

    test ":debug returns text-base-content/60" do
      assert View.level_color(:debug) == "text-base-content/60"
    end
  end

  describe "component_label/1" do
    test "returns atom stringified for :pipeline" do
      assert View.component_label(:pipeline) == "pipeline"
    end

    test "returns atom stringified for :live_view" do
      assert View.component_label(:live_view) == "live_view"
    end

    test "returns system for nil" do
      assert View.component_label(nil) == "system"
    end
  end

  describe "component_badge_class/1" do
    test "returns a dedicated chip-* class for every known component" do
      for component <- View.known_components() do
        result = View.component_badge_class(component)

        assert result == "chip-#{component}",
               "expected #{component} to map to chip-#{component}, got #{inspect(result)}"
      end
    end

    test "returns chip-system for nil (unknown fallback)" do
      assert View.component_badge_class(nil) == "chip-system"
    end

    test "every known component gets a distinct class" do
      classes = Enum.map(View.known_components(), &View.component_badge_class/1)
      assert classes == Enum.uniq(classes)
    end
  end

  describe "format_line/1" do
    test "produces [HH:MM:SS.mmm] [level] [component] message format" do
      # We need a fixed time to make the timestamp predictable in format
      entry =
        build_entry(
          timestamp: ~U[2026-04-05 14:30:45.123Z],
          level: :info,
          component: :pipeline,
          message: "pipeline started"
        )

      result = View.format_line(entry)

      # Format: "[HH:MM:SS.mmm] [level] [component] message"
      assert String.match?(
               result,
               ~r/^\[\d{2}:\d{2}:\d{2}\.\d{3}\] \[info\] \[pipeline\] pipeline started$/
             )
    end

    test "formats error level entries correctly" do
      entry = build_entry(level: :error, component: :tmdb, message: "request failed")
      result = View.format_line(entry)
      assert String.contains?(result, "[error]")
      assert String.contains?(result, "[tmdb]")
      assert String.contains?(result, "request failed")
    end
  end

  describe "format_lines/1" do
    test "reverses entries from newest-first to chronological and joins with newlines" do
      entry_one = build_entry(id: 1, message: "first")
      entry_two = build_entry(id: 2, message: "second")
      entry_three = build_entry(id: 3, message: "third")

      # Input is newest-first: [third, second, first]
      result = View.format_lines([entry_three, entry_two, entry_one])
      lines = String.split(result, "\n")

      assert length(lines) == 3
      # After reversal, should be chronological: first, second, third
      assert String.contains?(Enum.at(lines, 0), "first")
      assert String.contains?(Enum.at(lines, 1), "second")
      assert String.contains?(Enum.at(lines, 2), "third")
    end

    test "returns empty string for empty list" do
      assert View.format_lines([]) == ""
    end

    test "returns single line with no trailing newline for one entry" do
      entry = build_entry(message: "only entry")
      result = View.format_lines([entry])
      refute String.contains?(result, "\n")
    end
  end

  describe "chip_state_class/2" do
    test "returns console-chip-active for a :show component" do
      filter = Filter.new(components: %{pipeline: :show}, default_component: :hide)
      assert View.chip_state_class(filter, :pipeline) == "console-chip-active"
    end

    test "returns console-chip-inactive for a :hide component" do
      filter = Filter.new(components: %{pipeline: :hide}, default_component: :show)
      assert View.chip_state_class(filter, :pipeline) == "console-chip-inactive"
    end

    test "falls back to default_component when component not explicitly set" do
      filter = Filter.new(components: %{}, default_component: :show)
      assert View.chip_state_class(filter, :tmdb) == "console-chip-active"
    end

    test "falls back to default_component :hide when component not set" do
      filter = Filter.new(components: %{}, default_component: :hide)
      assert View.chip_state_class(filter, :tmdb) == "console-chip-inactive"
    end
  end

  describe "level_button_class/2" do
    test "returns btn-active when filter level matches the given level" do
      filter = Filter.new(level: :info)
      assert View.level_button_class(filter, :info) == "btn-active"
    end

    test "returns empty string when filter level does not match" do
      filter = Filter.new(level: :info)
      assert View.level_button_class(filter, :error) == ""
    end

    test "returns btn-active for :error when filter is :error" do
      filter = Filter.new(level: :error)
      assert View.level_button_class(filter, :error) == "btn-active"
    end

    test "returns empty string for :info when filter is :warning" do
      filter = Filter.new(level: :warning)
      assert View.level_button_class(filter, :info) == ""
    end
  end

  describe "pause_button_label/1" do
    test "returns 'resume' when paused" do
      assert View.pause_button_label(true) == "resume"
    end

    test "returns 'pause' when not paused" do
      assert View.pause_button_label(false) == "pause"
    end
  end

  describe "only_search_query_differs?/2" do
    test "returns true when filters differ only in search text" do
      base = Filter.new_with_defaults()
      with_search = %{base | search: "error"}

      assert View.only_search_query_differs?(base, with_search)
      assert View.only_search_query_differs?(with_search, base)
    end

    test "returns false when search is identical" do
      filter = %{Filter.new_with_defaults() | search: "same"}
      refute View.only_search_query_differs?(filter, filter)
    end

    test "returns false when level differs" do
      base = Filter.new_with_defaults()
      changed = %{base | level: :warning, search: "x"}
      refute View.only_search_query_differs?(base, changed)
    end

    test "returns false when a component visibility differs" do
      base = Filter.new_with_defaults()
      toggled = Filter.toggle_component(base, :pipeline)
      # Even with the same search, component difference should win.
      refute View.only_search_query_differs?(base, toggled)
      # Adding a search diff on top still returns false.
      refute View.only_search_query_differs?(base, %{toggled | search: "x"})
    end

    test "returns false when default_component differs" do
      base = Filter.new_with_defaults()
      changed = %{base | default_component: :hide, search: "x"}
      refute View.only_search_query_differs?(base, changed)
    end
  end

  describe "entry_search_text/1" do
    test "returns lowercased message for search data attribute" do
      entry = build_entry(message: "Pipeline STARTED successfully")
      assert View.entry_search_text(entry) == "pipeline started successfully"
    end

    test "returns empty string for empty message" do
      entry = build_entry(message: "")
      assert View.entry_search_text(entry) == ""
    end

    test "already lowercase message passes through unchanged" do
      entry = build_entry(message: "already lowercase")
      assert View.entry_search_text(entry) == "already lowercase"
    end
  end
end
