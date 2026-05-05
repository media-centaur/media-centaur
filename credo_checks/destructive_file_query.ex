defmodule MediaCentarr.Credo.Checks.DestructiveFileQuery do
  use Credo.Check,
    id: "MC0015",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Static guard against the durability bug class that motivated
      `MediaCentarr.Watcher.AbsencePolicy`: a `Repo.delete_all` on a
      file-presence-tracking table that doesn't filter on `:watch_dir`
      can silently destroy data for a drive that's currently
      unmounted (file marked absent because we can't see it, not
      because it's gone — destroying it cascades through
      `MediaCentarr.Library.FileEventHandler` to the entity rows on
      that drive).

      This check flags `Repo.delete_all(from(x in <Schema>, ...))`
      where `<Schema>` is `KnownFile` or `WatchedFile` and the query
      AST contains no reference to `:watch_dir`. The intent is to
      force the destructive author to either:

        1. Add an availability filter — usually `where: x.watch_dir
           in ^MediaCentarr.Watcher.AbsencePolicy.available_watch_dirs()`,
           or
        2. Add an explicit override comment that documents *why* the
           destructive op is safe without one (e.g. operator action,
           inotify-confirmed deletion, IDs already filtered upstream).

      Override:

          # credo:disable-for-next-line MediaCentarr.Credo.Checks.DestructiveFileQuery
          # <one-line reason>
          Repo.delete_all(from(w in WatchedFile, where: w.id in ^ids))

      Schemas wider than KnownFile/WatchedFile (entities, images, …)
      are deliberately out of scope — they get destroyed via
      `EntityCascade`, which is downstream of file-presence deletes.
      Fixing the file-presence guard prevents the cascade from running
      spuriously without false-positiving every entity-mutation site.
      """
    ]

  @target_schemas [:KnownFile, :WatchedFile]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # Repo.delete_all(query) — single-arg form.
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Repo]}, :delete_all]}, meta, [query_ast]} = ast,
         issues,
         issue_meta
       ) do
    {ast, maybe_issue(query_ast, meta, issues, issue_meta)}
  end

  # Repo.delete_all(query, opts) — two-arg form.
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Repo]}, :delete_all]}, meta, [query_ast, _opts]} = ast,
         issues,
         issue_meta
       ) do
    {ast, maybe_issue(query_ast, meta, issues, issue_meta)}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # Examine the query passed to delete_all and decide whether it warrants an issue.
  defp maybe_issue(query_ast, meta, issues, issue_meta) do
    case classify_query(query_ast) do
      {:target, schema} ->
        if mentions_watch_dir?(query_ast) do
          issues
        else
          [issue_for(issue_meta, "Repo.delete_all on #{schema}", meta[:line]) | issues]
        end

      :other ->
        issues
    end
  end

  # Recognise `from(<binding> in TargetSchema, ...)` where TargetSchema
  # appears as the *last* segment of an aliased module name (so both
  # bare `KnownFile` and `MediaCentarr.Watcher.KnownFile` match).
  defp classify_query({:from, _, [{:in, _, [_binding, {:__aliases__, _, schema_path}]} | _rest]}) do
    case List.last(schema_path) do
      schema when schema in @target_schemas -> {:target, schema}
      _ -> :other
    end
  end

  defp classify_query(_other), do: :other

  # Walk the AST looking for any `:watch_dir` atom — covers
  # `where: x.watch_dir in ...` (`{:watch_dir, _, _}` access) as well
  # as map keys, atom literals, and Keyword entries.
  defp mentions_watch_dir?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        :watch_dir, _acc -> {:watch_dir, true}
        {:watch_dir, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Destructive query on a file-presence table without a `:watch_dir` filter — " <>
          "this is the bug class `MediaCentarr.Watcher.AbsencePolicy` exists to prevent. " <>
          "Add a `where: ... in ^AbsencePolicy.available_watch_dirs()` clause, or add an " <>
          "explicit override comment documenting why this destructive op is safe without one.",
      trigger: trigger,
      line_no: line_no || 0
    )
  end
end
