defmodule MediaCentaur.Credo.Checks.TargetStatusContract do
  use Credo.Check,
    id: "MC0014",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Code outside `MediaCentaur.Acquisition.TargetStatus` and the schema
      module `MediaCentaur.Acquisition.Target` must not use the `in`
      operator with an inline list of target-status strings (e.g.
      `status in ["acquired", "succeeded", "failed", "cancelled"]`,
      `status in ["seeking", "acquired"]`). Use the bucket helpers from
      `TargetStatus` instead — `in_flight/0`, `terminal/0`,
      `terminal_success/0`, `terminal_failure/0`, `rearmable/0`,
      `cancellable/0`, and their `?` predicates — which return the same
      lists from a single source of truth.

          # preferred
          alias MediaCentaur.Acquisition.TargetStatus

          if TargetStatus.terminal?(target.status), do: …
          where: t.status in ^TargetStatus.in_flight()

          # NOT preferred — the v0.31.0 silent-miscategorization bug was
          # caused by an inline list like this missing one of the values
          status in ["acquired", "succeeded", "failed", "cancelled"]
          status in ["seeking", "acquired"]

      Why: when a new status is introduced, the only places that need to
      learn about it are `TargetStatus` (the source of truth) and `Target`
      (the schema that writes the literal). Inlined lists elsewhere
      become silently-wrong on the first new-status addition.

      The check exempts:
        * `lib/media_centaur/acquisition/target_status.ex` — source of truth
        * `lib/media_centaur/acquisition/target.ex` — the schema that writes literals
        * `priv/repo/migrations/` — DB-level constants
        * test files
      """
    ]

  @source_of_truth "lib/media_centaur/acquisition/target_status.ex"
  @schema "lib/media_centaur/acquisition/target.ex"

  # A rename that moves either exempted file silently disarms this check:
  # every `String.contains?/2` below stops matching, the check keeps
  # walking every source file, and it can never fire again. That is
  # exactly what happened to this check's predecessor — it guarded
  # `grab_status.ex`/`grab.ex`, both of which were deleted in the
  # Grab→Target rename, leaving acquisition dispatch unprotected for
  # months. Fail the build instead.
  for path <- [@source_of_truth, @schema] do
    if !File.exists?(Path.expand(path, Path.join(__DIR__, ".."))) do
      raise CompileError,
        description:
          "MC0014 (TargetStatusContract) exempts #{path}, which does not exist. " <>
            "If the module moved, update the exemption paths and @target_statuses; " <>
            "if it was deleted, retire the check. Do not leave it pointing at a dead path."
    end
  end

  @target_statuses ~w(seeking acquired succeeded failed cancelled)

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    cond do
      String.contains?(filename, @source_of_truth) ->
        []

      String.contains?(filename, @schema) ->
        []

      String.contains?(filename, "priv/repo/migrations/") ->
        []

      String.starts_with?(filename, "test/") or String.contains?(filename, "/test/") ->
        []

      true ->
        issue_meta = IssueMeta.for(source_file, params)
        Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  # Match `something in [str1, str2, ...]` where every str is a known
  # target-status string. Two-element-or-larger lists only — single-element
  # lists are likely intentional one-state pattern matches.
  defp traverse({:in, meta, [_left, list]} = ast, issues, issue_meta)
       when is_list(list) and length(list) >= 2 do
    if all_target_statuses?(list) do
      sample = Enum.map_join(list, ", ", &inspect_string/1)
      {ast, [issue_for(issue_meta, "in [" <> sample <> "]", meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp all_target_statuses?(elements) do
    Enum.all?(elements, fn
      str when is_binary(str) -> str in @target_statuses
      _ -> false
    end)
  end

  defp inspect_string(s) when is_binary(s), do: ~s("#{s}")
  defp inspect_string(other), do: inspect(other)

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Inline list of target-status strings — use a bucket from " <>
          "`MediaCentaur.Acquisition.TargetStatus` (`in_flight/0`, `terminal/0`, " <>
          "`terminal_success/0`, `terminal_failure/0`) so adding a new status only " <>
          "requires editing one file.",
      trigger: trigger,
      line_no: line_no || 1
    )
  end
end
