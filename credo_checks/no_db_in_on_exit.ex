defmodule MediaCentaur.Credo.Checks.NoDbInOnExit do
  use Credo.Check,
    id: "MC0018",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      `ExUnit.Callbacks.on_exit/2` runs its callback in a dedicated
      `ExUnit.OnExitHandler` process — *not* the test process. That
      handler doesn't own the test's `Ecto.Adapters.SQL.Sandbox`
      connection, so any DB write from inside `on_exit` races against
      sandbox teardown and intermittently raises
      `DBConnection.OwnershipError` or "no process" exits under
      concurrent-test load.

      The sandbox already rolls back the test body's writes
      automatically. The only state that needs explicit cleanup is
      *in-memory* — `:persistent_term`, `Application` env, ETS
      tables, etc. Those are safe in `on_exit`.

          # NOT allowed — DB write in on_exit
          setup do
            on_exit(fn ->
              Config.update(:exclude_dirs, [])  # racy!
            end)
          end

          # Allowed — in-memory cache restore is safe in on_exit
          setup do
            original = :persistent_term.get({Config, :config})
            on_exit(fn -> :persistent_term.put({Config, :config}, original) end)
          end

          # Allowed — reset at start of next test, in test process
          setup do
            Config.update(:exclude_dirs, [])
            :ok
          end

      Source: `campaigns/test-isolation-hardening.md` — Category A.
      """
    ]

  # Names that hit the DB (writes specifically — reads are harmless
  # in on_exit because they fail loudly without retry behaviour).
  # Local + qualified call detection both supported.
  @forbidden_calls [
    {[:Config], :update},
    {[:MediaCentaur, :Config], :update},
    {[:Settings], :find_or_create_entry},
    {[:Settings], :find_or_create_entry!},
    {[:MediaCentaur, :Settings], :find_or_create_entry},
    {[:MediaCentaur, :Settings], :find_or_create_entry!},
    {[:Repo], :insert},
    {[:Repo], :insert!},
    {[:Repo], :update},
    {[:Repo], :update!},
    {[:Repo], :delete},
    {[:Repo], :delete!},
    {[:Repo], :insert_all},
    {[:Repo], :update_all},
    {[:Repo], :delete_all},
    {[:Repo], :transaction}
  ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if test_path?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_path?(filename) do
    String.starts_with?(filename, "test/") or String.contains?(filename, "/test/")
  end

  # `on_exit(fn -> body end)` — scan the body for forbidden calls.
  defp traverse({:on_exit, _meta, [{:fn, _, clauses}]} = ast, issues, issue_meta) do
    {ast, scan_clauses(clauses, issue_meta) ++ issues}
  end

  # `on_exit(name, fn -> body end)` — second-arg variant.
  defp traverse({:on_exit, _meta, [_name, {:fn, _, clauses}]} = ast, issues, issue_meta) do
    {ast, scan_clauses(clauses, issue_meta) ++ issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp scan_clauses(clauses, issue_meta) do
    Enum.flat_map(clauses, fn {:->, _meta, [_args, body]} ->
      scan_body(body, issue_meta)
    end)
  end

  defp scan_body(body, issue_meta) do
    {_ast, found} = Macro.prewalk(body, [], &collect_forbidden(&1, &2, issue_meta))
    found
  end

  # Qualified call: `Foo.Bar.fun(...)` shape.
  defp collect_forbidden(
         {{:., meta, [{:__aliases__, _, mod_parts}, fun]}, _, _args} = ast,
         acc,
         issue_meta
       ) do
    if {mod_parts, fun} in @forbidden_calls do
      {ast, [issue_for(issue_meta, format_call(mod_parts, fun), meta[:line]) | acc]}
    else
      {ast, acc}
    end
  end

  defp collect_forbidden(ast, acc, _issue_meta), do: {ast, acc}

  defp format_call(mod_parts, fun), do: "#{Enum.join(mod_parts, ".")}.#{fun}"

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}` inside `on_exit` runs in `ExUnit.OnExitHandler` " <>
          "without the test's sandbox ownership and races against teardown. " <>
          "Move the DB-touching cleanup to the start of `setup` (runs in the " <>
          "test process), or rely on per-test sandbox rollback. " <>
          "See `campaigns/test-isolation-hardening.md`.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
