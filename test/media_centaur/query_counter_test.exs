defmodule MediaCentaur.QueryCounterTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.QueryCounter
  alias MediaCentaur.Library.Movie

  describe "count/1" do
    test "returns ({result, []}) when the callback issues no queries" do
      {result, queries} = QueryCounter.count(fn -> 42 end)

      assert result == 42
      assert queries == []
    end

    test "captures one query per Repo call and returns the callback's result" do
      {result, queries} = QueryCounter.count(fn -> Repo.aggregate(Movie, :count, :id) end)

      assert is_integer(result)
      assert length(queries) == 1
      assert [{source, sql}] = queries
      assert is_binary(sql)
      # source is the table name (binary or nil for ad-hoc fragments)
      assert source == nil or is_binary(source)
    end

    test "captures multiple queries in invocation order" do
      {_result, queries} =
        QueryCounter.count(fn ->
          Repo.aggregate(Movie, :count, :id)
          Repo.aggregate(Movie, :count, :id)
          Repo.aggregate(Movie, :count, :id)
        end)

      assert length(queries) == 3
    end

    test "detaches the telemetry handler after the callback returns" do
      handlers_before = :telemetry.list_handlers([:media_centaur, :repo, :query])

      {_result, _queries} = QueryCounter.count(fn -> :ok end)

      handlers_after = :telemetry.list_handlers([:media_centaur, :repo, :query])

      assert length(handlers_after) == length(handlers_before),
             "QueryCounter must detach its handler — found a leak after count/1 returned"
    end

    test "detaches the telemetry handler when the callback raises" do
      handlers_before = :telemetry.list_handlers([:media_centaur, :repo, :query])

      assert_raise RuntimeError, "boom", fn ->
        QueryCounter.count(fn -> raise "boom" end)
      end

      handlers_after = :telemetry.list_handlers([:media_centaur, :repo, :query])

      assert length(handlers_after) == length(handlers_before),
             "QueryCounter must detach its handler — even on exception"
    end
  end

  describe "process scoping" do
    test "ignores queries emitted by processes outside the scope" do
      {_result, queries} =
        QueryCounter.count(fn ->
          Task.await(Task.async(fn -> Repo.aggregate(Movie, :count, :id) end))
          :ok
        end)

      assert queries == [],
             """
             count/1 must scope to the calling process. A background worker issuing
             a query during the measured window inflated the count by \
             #{length(queries)} — this is what makes query budgets flake under
             full-suite parallelism.
             """
    end

    test "from: extends the scope with pids derived from the callback's result" do
      {task, queries} =
        QueryCounter.count(
          fn ->
            task = Task.async(fn -> Repo.aggregate(Movie, :count, :id) end)
            Task.await(task)
            task
          end,
          from: fn task -> [task.pid] end
        )

      assert %Task{} = task

      assert length(queries) == 1,
             "expected the scoped task's single query, got #{length(queries)}"
    end

    test "from: still counts the caller's own queries" do
      {_task, queries} =
        QueryCounter.count(
          fn ->
            task = Task.async(fn -> Repo.aggregate(Movie, :count, :id) end)
            Task.await(task)
            Repo.aggregate(Movie, :count, :id)
            task
          end,
          from: fn task -> [task.pid] end
        )

      assert length(queries) == 2,
             "expected one query from the task and one from the caller, got #{length(queries)}"
    end

    test "from: excludes processes it does not name" do
      {_task, queries} =
        QueryCounter.count(
          fn ->
            Task.await(Task.async(fn -> Repo.aggregate(Movie, :count, :id) end))
            Task.await(Task.async(fn -> Repo.aggregate(Movie, :count, :id) end))
            :ok
          end,
          from: fn _ -> [] end
        )

      assert queries == []
    end
  end

  describe "format/1" do
    test "renders an empty list as the empty string" do
      assert QueryCounter.format([]) == ""
    end

    test "renders {source, sql} tuples one per line" do
      formatted =
        QueryCounter.format([
          {"library_movies", "SELECT * FROM library_movies"},
          {nil, "SELECT 1"}
        ])

      assert formatted ==
               ~s|  "library_movies": SELECT * FROM library_movies\n  nil: SELECT 1|
    end
  end
end
