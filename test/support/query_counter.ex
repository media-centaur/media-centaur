defmodule MediaCentaur.QueryCounter do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Counts `MediaCentaur.Repo` queries issued during the execution of a
  zero-arity callback via the `[:media_centaur, :repo, :query]`
  telemetry event Ecto emits by default.

  Used by `MediaCentaurWeb.NoDbOnRenderTest` (and any other suite that
  needs to assert a bounded mount-time query budget) to lock in the
  no-DB-on-render contract that the in-memory projection architecture
  (ADR-041, Library Schema v2 Phase 3) ships.

  ## Process scoping

  Ecto emits the query event **synchronously in the process that ran the
  query**, so an unscoped handler counts queries from every process in
  the VM. Background workers (projection `Cache.Worker`s refreshing on
  the entity-creation PubSub, etc.) firing during the measured window
  inflate the count — a budget that passes in isolation flakes under
  full-suite parallelism.

  `count/1` therefore counts **only the calling process**. When the work
  under measurement runs elsewhere — a LiveView mounts in its own
  process, so `live/2` issues none of its queries from the test — name
  that process with `:from`, a function of the callback's result. It is
  applied after the callback returns, which is what makes a pid that
  only exists once the callback finishes (`view.pid`) usable as a scope.

  ## Usage

      {{:ok, view, _html}, queries} =
        MediaCentaur.QueryCounter.count(
          fn -> live(conn, "/library") end,
          from: fn {:ok, view, _html} -> [view.pid] end
        )

      assert length(queries) <= 1

  Each entry in the returned `queries` list is a `{source, sql}` tuple,
  where `source` is the table name and `sql` is the raw SQL string —
  enough to debug a budget overrun without leaking schema details.
  """

  @event [:media_centaur, :repo, :query]

  @doc """
  Runs `fun` and returns `{result, queries}` where `queries` is a list
  of `{source, sql}` tuples (one per `Repo` query emitted while `fun`
  was on the call stack, **by a process in scope**).

  The scope is the calling process, plus any pids returned by the
  `:from` option — a 1-arity function applied to `fun`'s result once it
  returns. See the moduledoc on process scoping; an unscoped count is
  a flake waiting for a background worker.

  Attaches a telemetry handler keyed by a fresh `make_ref/0`, so
  concurrent `count/2` invocations in the same process don't interleave
  events. The handler is always detached in an `after` block.
  """
  @spec count((-> result), keyword) :: {result, [{String.t() | nil, String.t()}]}
        when result: var
  def count(fun, opts \\ []) when is_function(fun, 0) do
    ref = make_ref()
    parent = self()
    handler_id = {__MODULE__, ref}

    :ok =
      :telemetry.attach(
        handler_id,
        @event,
        fn _event, _measurements, metadata, _config ->
          send(
            parent,
            {:query, ref, self(), Map.get(metadata, :source), Map.get(metadata, :query)}
          )
        end,
        nil
      )

    try do
      result = fun.()
      queries = drain(ref, scope(opts[:from], result, parent), [])
      {result, queries}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp scope(nil, _result, parent), do: MapSet.new([parent])

  defp scope(from, result, parent) when is_function(from, 1) do
    MapSet.new([parent | from.(result)])
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

  defp drain(ref, scope, acc) do
    receive do
      {:query, ^ref, pid, source, sql} ->
        if MapSet.member?(scope, pid),
          do: drain(ref, scope, [{source, sql} | acc]),
          else: drain(ref, scope, acc)
    after
      0 -> Enum.reverse(acc)
    end
  end
end
