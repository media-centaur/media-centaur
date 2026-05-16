defmodule MediaCentarr.QueryCounter do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Counts `MediaCentarr.Repo` queries issued during the execution of a
  zero-arity callback via the `[:media_centarr, :repo, :query]`
  telemetry event Ecto emits by default.

  Used by `MediaCentarrWeb.NoDbOnRenderTest` (and any other suite that
  needs to assert a bounded mount-time query budget) to lock in the
  no-DB-on-render contract that the in-memory projection architecture
  (ADR-041, Library Schema v2 Phase 3) ships.

  ## Usage

      {result, queries} = MediaCentarr.QueryCounter.count(fn ->
        live(conn, "/library")
      end)

      assert length(queries) <= 1
      assert {:ok, _view, _html} = result

  Each entry in the returned `queries` list is a `{source, sql}` tuple,
  where `source` is the table name and `sql` is the raw SQL string —
  enough to debug a budget overrun without leaking schema details.
  """

  @event [:media_centarr, :repo, :query]

  @doc """
  Runs `fun` and returns `{result, queries}` where `queries` is a list
  of `{source, sql}` tuples (one per `Repo` query Ecto emitted while
  `fun` was on the call stack).

  Attaches a telemetry handler scoped by a fresh `make_ref/0`, so
  multiple concurrent `count/1` invocations within the same process
  don't interleave events. The handler is always detached in an
  `after` block.
  """
  @spec count((-> result)) :: {result, [{String.t() | nil, String.t()}]}
        when result: var
  def count(fun) when is_function(fun, 0) do
    ref = make_ref()
    parent = self()
    handler_id = {__MODULE__, ref}

    :ok =
      :telemetry.attach(
        handler_id,
        @event,
        fn _event, _measurements, metadata, _config ->
          send(parent, {:query, ref, Map.get(metadata, :source), Map.get(metadata, :query)})
        end,
        nil
      )

    try do
      result = fun.()
      queries = drain(ref, [])
      {result, queries}
    after
      :telemetry.detach(handler_id)
    end
  end

  @doc """
  Convenience formatter for assertion failure messages. Renders the
  `{source, sql}` list as one query per line, prefixed by the source
  table name — easier to read than `inspect/1` on a long list.
  """
  @spec format([{String.t() | nil, String.t()}]) :: String.t()
  def format(queries) do
    Enum.map_join(queries, "\n", fn {source, sql} ->
      "  #{inspect(source)}: #{sql}"
    end)
  end

  defp drain(ref, acc) do
    receive do
      {:query, ^ref, source, sql} -> drain(ref, [{source, sql} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
