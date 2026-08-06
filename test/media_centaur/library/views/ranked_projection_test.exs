defmodule MediaCentaur.Library.Views.RankedProjectionTest do
  @moduledoc """
  The storage primitive every rank-keyed Library projection delegates to
  (ADR-041). A defect here is repo-wide — `ContinueWatching`,
  `RecentlyAdded`, `HeroCandidates`, and `Browse` all read and write
  through these four functions.

  Tested with throwaway table names rather than the real projection
  tables, so this never races the `Cache.Worker` or a sibling test.
  """
  use ExUnit.Case, async: false

  alias MediaCentaur.Library.Views.RankedProjection
  alias MediaCentaur.Topics

  defp unique_table do
    table = :"ranked_projection_test_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      case :ets.whereis(table) do
        :undefined -> :ok
        _ref -> :ets.delete(table)
      end
    end)

    table
  end

  describe "ensure_table/1" do
    test "creates the table when absent and is idempotent" do
      table = unique_table()

      assert :ets.whereis(table) == :undefined
      assert :ok = RankedProjection.ensure_table(table)
      refute :ets.whereis(table) == :undefined

      # A second call must not reset the table — projections call this on
      # every refresh, and a reset would drop rows mid-read.
      :ets.insert(table, {0, :sentinel})
      assert :ok = RankedProjection.ensure_table(table)
      assert :ets.tab2list(table) == [{0, :sentinel}]
    end
  end

  describe "replace_rows/4" do
    test "keys rows by 0-based rank in the order given" do
      table = unique_table()

      assert :ok = RankedProjection.replace_rows(table, :test_view, [:a, :b, :c])

      assert RankedProjection.read_from_ets(table, nil) == [:a, :b, :c]
      assert :ets.lookup(table, 0) == [{0, :a}]
      assert :ets.lookup(table, 2) == [{2, :c}]
    end

    test "replaces every previous row rather than merging" do
      table = unique_table()

      RankedProjection.replace_rows(table, :test_view, [:a, :b, :c, :d])
      RankedProjection.replace_rows(table, :test_view, [:x])

      # A merge would leave ranks 1..3 behind from the longer first write.
      assert RankedProjection.read_from_ets(table, nil) == [:x]
    end

    test "creates the table when it does not exist yet" do
      table = unique_table()

      assert :ok = RankedProjection.replace_rows(table, :test_view, [:only])
      assert RankedProjection.read_from_ets(table, nil) == [:only]
    end

    test "an empty list clears the projection" do
      table = unique_table()

      RankedProjection.replace_rows(table, :test_view, [:a, :b])
      RankedProjection.replace_rows(table, :test_view, [])

      assert RankedProjection.read_from_ets(table, nil) == []
    end

    test "broadcasts {:library_view_updated, view_tag} on library:views" do
      table = unique_table()
      Topics.subscribe(Topics.library_views())

      RankedProjection.replace_rows(table, :my_view, [:a])

      assert_receive {:library_view_updated, :my_view}
    end

    test ":rank_field stamps the assigned rank into each item" do
      table = unique_table()
      items = [%{name: "first", rank: nil}, %{name: "second", rank: nil}]

      RankedProjection.replace_rows(table, :test_view, items, rank_field: :rank)

      assert [%{name: "first", rank: 0}, %{name: "second", rank: 1}] =
               RankedProjection.read_from_ets(table, nil)
    end

    test "without :rank_field the items are stored untouched" do
      table = unique_table()
      items = [%{name: "first", rank: :untouched}]

      RankedProjection.replace_rows(table, :test_view, items)

      assert [%{name: "first", rank: :untouched}] = RankedProjection.read_from_ets(table, nil)
    end
  end

  describe "read_from_ets/2" do
    test "returns rows in rank order regardless of insertion order" do
      table = unique_table()
      RankedProjection.ensure_table(table)

      # `:ordered_set` iterates by key, so a scrambled insert still reads
      # back rank-sorted — this is why the projections skip an explicit sort.
      :ets.insert(table, [{2, :c}, {0, :a}, {1, :b}])

      assert RankedProjection.read_from_ets(table, nil) == [:a, :b, :c]
    end

    test "caps at limit, and a limit above the row count returns everything" do
      table = unique_table()
      RankedProjection.replace_rows(table, :test_view, [:a, :b, :c])

      assert RankedProjection.read_from_ets(table, 2) == [:a, :b]
      assert RankedProjection.read_from_ets(table, 99) == [:a, :b, :c]
      assert RankedProjection.read_from_ets(table, 0) == []
    end
  end

  describe "read/3" do
    test "reads from ETS when the table exists, without calling the fallback" do
      table = unique_table()
      RankedProjection.replace_rows(table, :test_view, [:cached])

      result = RankedProjection.read(table, nil, fn -> raise "fallback must not run" end)

      assert result == [:cached]
    end

    test "falls back to the database reader when the table is absent" do
      table = unique_table()

      assert RankedProjection.read(table, nil, fn -> [:from_db] end) == [:from_db]
    end

    test "applies limit on the ETS path but leaves the fallback to honour its own" do
      table = unique_table()
      RankedProjection.replace_rows(table, :test_view, [:a, :b, :c])

      assert RankedProjection.read(table, 2, fn -> [] end) == [:a, :b]

      absent = unique_table()
      assert RankedProjection.read(absent, 1, fn -> [:x, :y] end) == [:x, :y]
    end
  end
end
