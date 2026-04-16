defmodule MediaCentarr.Console.FilterTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Console.Entry
  alias MediaCentarr.Console.Filter

  defp build_entry(overrides) do
    defaults = [
      id: 1,
      timestamp: DateTime.utc_now(),
      level: :info,
      component: :pipeline,
      message: "test message"
    ]

    Entry.new(Keyword.merge(defaults, overrides))
  end

  describe "matches?/2 — level floor" do
    test "entry at :debug passes filter with level :debug" do
      entry = build_entry(level: :debug)
      filter = Filter.new(level: :debug)
      assert Filter.matches?(entry, filter)
    end

    test "entry at :debug fails filter with level :info" do
      entry = build_entry(level: :debug)
      filter = Filter.new(level: :info)
      refute Filter.matches?(entry, filter)
    end

    test "entry at :info passes filter with level :info" do
      entry = build_entry(level: :info)
      filter = Filter.new(level: :info)
      assert Filter.matches?(entry, filter)
    end

    test "entry at :info fails filter with level :warning" do
      entry = build_entry(level: :info)
      filter = Filter.new(level: :warning)
      refute Filter.matches?(entry, filter)
    end

    test "entry at :warning passes filter with level :warning" do
      entry = build_entry(level: :warning)
      filter = Filter.new(level: :warning)
      assert Filter.matches?(entry, filter)
    end

    test "entry at :warning fails filter with level :error" do
      entry = build_entry(level: :warning)
      filter = Filter.new(level: :error)
      refute Filter.matches?(entry, filter)
    end

    test "entry at :error passes filter with level :error" do
      entry = build_entry(level: :error)
      filter = Filter.new(level: :error)
      assert Filter.matches?(entry, filter)
    end

    test "entry at :error passes filter with level :debug" do
      entry = build_entry(level: :error)
      filter = Filter.new(level: :debug)
      assert Filter.matches?(entry, filter)
    end

    test "entry at :info fails filter with level :error" do
      entry = build_entry(level: :info)
      filter = Filter.new(level: :error)
      refute Filter.matches?(entry, filter)
    end
  end

  describe "matches?/2 — component visibility" do
    test "entry passes when component is explicitly :show" do
      entry = build_entry(component: :pipeline)
      filter = Filter.new(components: %{pipeline: :show})
      assert Filter.matches?(entry, filter)
    end

    test "entry fails when component is explicitly :hide" do
      entry = build_entry(component: :pipeline)
      filter = Filter.new(components: %{pipeline: :hide})
      refute Filter.matches?(entry, filter)
    end

    test "unknown component uses default_component :show" do
      entry = build_entry(component: :some_unknown)
      filter = Filter.new(components: %{}, default_component: :show)
      assert Filter.matches?(entry, filter)
    end

    test "unknown component uses default_component :hide" do
      entry = build_entry(component: :some_unknown)
      filter = Filter.new(components: %{}, default_component: :hide)
      refute Filter.matches?(entry, filter)
    end
  end

  describe "matches?/2 — search" do
    test "empty search string always matches" do
      entry = build_entry(message: "pipeline claimed 3 files")
      filter = Filter.new(search: "")
      assert Filter.matches?(entry, filter)
    end

    test "matching substring returns true" do
      entry = build_entry(message: "pipeline claimed 3 files")
      filter = Filter.new(search: "claimed")
      assert Filter.matches?(entry, filter)
    end

    test "search is case-insensitive" do
      entry = build_entry(message: "Pipeline Claimed 3 files")
      filter = Filter.new(search: "claimed")
      assert Filter.matches?(entry, filter)
    end

    test "search is case-insensitive for uppercase search" do
      entry = build_entry(message: "pipeline claimed 3 files")
      filter = Filter.new(search: "CLAIMED")
      assert Filter.matches?(entry, filter)
    end

    test "non-matching search returns false" do
      entry = build_entry(message: "pipeline claimed 3 files")
      filter = Filter.new(search: "tmdb")
      refute Filter.matches?(entry, filter)
    end
  end

  describe "matches?/2 — combined AND semantics" do
    test "entry passes when all three conditions are satisfied" do
      entry = build_entry(level: :warning, component: :pipeline, message: "something broke")
      filter = Filter.new(level: :info, components: %{pipeline: :show}, search: "broke")
      assert Filter.matches?(entry, filter)
    end

    test "entry fails when level fails even if component and search pass" do
      entry = build_entry(level: :debug, component: :pipeline, message: "something broke")
      filter = Filter.new(level: :info, components: %{pipeline: :show}, search: "broke")
      refute Filter.matches?(entry, filter)
    end

    test "entry fails when component is hidden even if level and search pass" do
      entry = build_entry(level: :info, component: :ecto, message: "query executed")
      filter = Filter.new(level: :info, components: %{ecto: :hide}, search: "query")
      refute Filter.matches?(entry, filter)
    end

    test "entry fails when search doesn't match even if level and component pass" do
      entry = build_entry(level: :info, component: :pipeline, message: "pipeline started")
      filter = Filter.new(level: :info, components: %{pipeline: :show}, search: "tmdb")
      refute Filter.matches?(entry, filter)
    end
  end

  describe "toggle_component/2" do
    test "flips :show to :hide" do
      filter = Filter.new(components: %{pipeline: :show})
      toggled = Filter.toggle_component(filter, :pipeline)
      assert toggled.components[:pipeline] == :hide
    end

    test "flips :hide to :show" do
      filter = Filter.new(components: %{pipeline: :hide})
      toggled = Filter.toggle_component(filter, :pipeline)
      assert toggled.components[:pipeline] == :show
    end

    test "toggles show to hide and back to show" do
      filter = Filter.new(components: %{pipeline: :show})

      after_first_toggle = Filter.toggle_component(filter, :pipeline)
      assert after_first_toggle.components[:pipeline] == :hide

      after_second_toggle = Filter.toggle_component(after_first_toggle, :pipeline)
      assert after_second_toggle.components[:pipeline] == :show
    end

    test "unknown component (not in map) defaults to :show then gets toggled to :hide" do
      filter = Filter.new(components: %{}, default_component: :show)
      toggled = Filter.toggle_component(filter, :pipeline)
      assert toggled.components[:pipeline] == :hide
    end
  end

  describe "solo_component/2" do
    test "only the given component is :show, all known others are :hide" do
      filter = Filter.new_with_defaults()
      soloed = Filter.solo_component(filter, :pipeline)

      assert soloed.components[:pipeline] == :show

      known_components = MediaCentarr.Console.View.known_components()

      for component <- known_components, component != :pipeline do
        assert soloed.components[component] == :hide,
               "expected #{component} to be :hide after solo_component(:pipeline)"
      end
    end

    test "solo on a filter where the target started :hide flips it to :show" do
      filter = Filter.new(components: %{pipeline: :show, tmdb: :hide, ecto: :show})
      soloed = Filter.solo_component(filter, :tmdb)

      assert soloed.components[:tmdb] == :show
      assert soloed.components[:pipeline] == :hide
      assert soloed.components[:ecto] == :hide
    end

    test "solo on an unknown component writes it explicitly as :show" do
      filter = Filter.new_with_defaults()
      unknown = :some_unrecognized_component

      soloed = Filter.solo_component(filter, unknown)

      assert soloed.components[unknown] == :show

      for known_component <- MediaCentarr.Console.View.known_components() do
        assert soloed.components[known_component] == :hide
      end
    end
  end

  describe "mute_component/2" do
    test "given component is :hide, all known others are :show" do
      filter = Filter.new_with_defaults()
      muted = Filter.mute_component(filter, :pipeline)

      assert muted.components[:pipeline] == :hide

      known_components = MediaCentarr.Console.View.known_components()

      for component <- known_components, component != :pipeline do
        assert muted.components[component] == :show,
               "expected #{component} to be :show after mute_component(:pipeline)"
      end
    end

    test "mute on an unknown component writes it explicitly as :hide" do
      filter = Filter.new_with_defaults()
      unknown = :some_unrecognized_component

      muted = Filter.mute_component(filter, unknown)

      assert muted.components[unknown] == :hide

      for known_component <- MediaCentarr.Console.View.known_components() do
        assert muted.components[known_component] == :show
      end
    end
  end

  describe "to_persistable/1 and from_persistable/1" do
    test "round-trip for a non-default filter" do
      filter = %Filter{
        level: :warning,
        components: %{pipeline: :show, ecto: :hide},
        default_component: :hide,
        search: "error"
      }

      persistable = Filter.to_persistable(filter)
      restored = Filter.from_persistable(persistable)

      assert restored.level == :warning
      assert restored.components[:pipeline] == :show
      assert restored.components[:ecto] == :hide
      assert restored.default_component == :hide
      assert restored.search == "error"
    end

    test "to_persistable converts atoms to strings" do
      filter = Filter.new(level: :info, default_component: :show)
      persistable = Filter.to_persistable(filter)
      assert persistable["level"] == "info"
      assert persistable["default_component"] == "show"
    end

    test "to_persistable produces string keys for components" do
      filter = Filter.new(components: %{pipeline: :show})
      persistable = Filter.to_persistable(filter)
      assert is_map(persistable["components"])
      assert persistable["components"]["pipeline"] == "show"
    end
  end

  describe "from_persistable/1" do
    test "tolerates missing keys by returning defaults" do
      restored = Filter.from_persistable(%{})
      assert restored.level == :info
      assert restored.default_component == :show
      assert restored.search == ""
    end

    test "tolerates invalid level atom by returning default :info" do
      restored = Filter.from_persistable(%{"level" => "not_a_valid_level_xyz"})
      assert restored.level == :info
    end

    test "ignores unknown keys" do
      restored = Filter.from_persistable(%{"level" => "debug", "unknown_key" => "irrelevant"})
      assert restored.level == :debug
    end

    test "returns a default filter for non-map input" do
      assert Filter.from_persistable(nil) == %Filter{}
      assert Filter.from_persistable("garbage") == %Filter{}
      assert Filter.from_persistable(42) == %Filter{}
      assert Filter.from_persistable([1, 2, 3]) == %Filter{}
    end

    test "tolerates invalid component atom keys in components map" do
      restored =
        Filter.from_persistable(%{
          "components" => %{
            "pipeline" => "show",
            "totally_unknown_atom_xyz_#{System.unique_integer([:positive])}" => "show"
          }
        })

      assert restored.components[:pipeline] == :show
      refute Map.has_key?(restored.components, nil)
    end
  end

  describe "search_lower cache" do
    test "Filter.new/1 populates search_lower from the search option" do
      assert Filter.new(search: "FOO").search_lower == "foo"
    end

    test "Filter.from_persistable/1 populates search_lower from the persisted search" do
      assert Filter.from_persistable(%{"search" => "BAR"}).search_lower == "bar"
    end
  end

  describe "new_with_defaults/0" do
    test "framework components are :hide by default" do
      filter = Filter.new_with_defaults()
      assert filter.components[:phoenix] == :hide
      assert filter.components[:ecto] == :hide
      assert filter.components[:live_view] == :hide
    end

    test "app components are :show by default" do
      filter = Filter.new_with_defaults()
      assert filter.components[:watcher] == :show
      assert filter.components[:pipeline] == :show
      assert filter.components[:tmdb] == :show
      assert filter.components[:playback] == :show
      assert filter.components[:library] == :show
      assert filter.components[:system] == :show
    end
  end
end
