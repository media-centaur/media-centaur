defmodule MediaCentarr.Credo.Checks.GrabStatusContract do
  use Credo.Check,
    id: "MC0014",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Code outside `MediaCentarr.Acquisition.GrabStatus` and the schema
      module `MediaCentarr.Acquisition.Grab` must not use the `in`
      operator with an inline list of grab-status strings (e.g.
      `status in ["grabbed", "abandoned", "cancelled"]`,
      `status in ["searching", "snoozed"]`). Use the bucket helpers from
      `GrabStatus` instead — `in_flight/0`, `terminal/0`,
      `terminal_failure/0` — which return the same lists from a single
      source of truth.

          # preferred
          alias MediaCentarr.Acquisition.GrabStatus

          if GrabStatus.terminal?(grab.status), do: …
          where: g.status in ^GrabStatus.in_flight()

          # NOT preferred — the v0.31.0 silent-miscategorization bug was
          # caused by an inline list like this missing one of the values
          status in ["grabbed", "abandoned", "cancelled"]
          status in ["searching", "snoozed"]

      Why: when a new status is introduced, the only places that need to
      learn about it are `GrabStatus` (the source of truth) and `Grab`
      (the schema that writes the literal). Inlined lists elsewhere
      become silently-wrong on the first new-status addition.

      The check exempts:
        * `lib/media_centarr/acquisition/grab_status.ex` — source of truth
        * `lib/media_centarr/acquisition/grab.ex` — the schema that writes literals
        * `priv/repo/migrations/` — DB-level constants
        * test files
      """
    ]

  @grab_statuses ~w(searching snoozed grabbed abandoned cancelled)

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    cond do
      String.contains?(filename, "lib/media_centarr/acquisition/grab_status.ex") ->
        []

      String.contains?(filename, "lib/media_centarr/acquisition/grab.ex") ->
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
  # grab-status string. Two-element-or-larger lists only — single-element
  # lists are likely intentional one-state pattern matches.
  defp traverse({:in, meta, [_left, list]} = ast, issues, issue_meta)
       when is_list(list) and length(list) >= 2 do
    if all_grab_statuses?(list) do
      sample = Enum.map_join(list, ", ", &inspect_string/1)
      {ast, [issue_for(issue_meta, "in [" <> sample <> "]", meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp all_grab_statuses?(elements) do
    Enum.all?(elements, fn
      str when is_binary(str) -> str in @grab_statuses
      _ -> false
    end)
  end

  defp inspect_string(s) when is_binary(s), do: ~s("#{s}")
  defp inspect_string(other), do: inspect(other)

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Inline list of grab-status strings — use a bucket from " <>
          "`MediaCentarr.Acquisition.GrabStatus` (`in_flight/0`, `terminal/0`, " <>
          "`terminal_failure/0`) so adding a new status only requires editing one file.",
      trigger: trigger,
      line_no: line_no || 1
    )
  end
end
