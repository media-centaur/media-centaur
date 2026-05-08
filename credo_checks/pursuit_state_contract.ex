defmodule MediaCentarr.Credo.Checks.PursuitStateContract do
  use Credo.Check,
    id: "MC0015",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Code outside `MediaCentarr.Acquisition.Pursuits.State` and the schema
      module `MediaCentarr.Acquisition.Pursuits.Pursuit` must not use the
      `in` operator with an inline list of pursuit-state strings or atoms
      (e.g. `state in ["active", "needs_decision"]`,
      `state in [:active, :needs_decision]`). Use the bucket helpers from
      `Pursuits.State` instead — `in_flight/0`, `terminal/0` — which
      return the same lists from a single source of truth.

          # preferred
          alias MediaCentarr.Acquisition.Pursuits.State

          if State.terminal?(pursuit.state), do: …
          where: p.state in ^State.in_flight()

          # NOT preferred
          state in ["active", "needs_decision"]
          state in [:active, :needs_decision]

      Why: this mirrors `MC0014 GrabStatusContract`. When a new pursuit
      state is introduced, only `Pursuits.State` (source of truth) and
      `Pursuit` (the schema that writes literals) need to learn about it.
      Inlined lists elsewhere become silently-wrong on the first
      new-state addition.

      The check exempts:
        * `lib/media_centarr/acquisition/pursuits/state.ex` — source of truth
        * `lib/media_centarr/acquisition/pursuits/pursuit.ex` — the schema that writes literals
        * `lib/media_centarr_web/components/acquisition/pursuit_style.ex` — view-model atom set lives here
        * `priv/repo/migrations/` — DB-level constants
        * test files
      """
    ]

  @pursuit_states ~w(active needs_decision satisfied exhausted cancelled)
  @pursuit_state_atoms [:active, :needs_decision, :satisfied, :exhausted, :cancelled]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    cond do
      String.contains?(filename, "lib/media_centarr/acquisition/pursuits/state.ex") ->
        []

      String.contains?(filename, "lib/media_centarr/acquisition/pursuits/pursuit.ex") ->
        []

      String.contains?(filename, "lib/media_centarr_web/components/acquisition/pursuit_style.ex") ->
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

  # Match `something in [item1, item2, ...]` where every item is a known
  # pursuit-state value (string or atom). Two-element-or-larger lists only —
  # single-element lists are likely intentional one-state pattern matches.
  defp traverse({:in, meta, [_left, list]} = ast, issues, issue_meta)
       when is_list(list) and length(list) >= 2 do
    if all_pursuit_states?(list) do
      sample = Enum.map_join(list, ", ", &inspect_value/1)
      {ast, [issue_for(issue_meta, "in [" <> sample <> "]", meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp all_pursuit_states?(elements) do
    Enum.all?(elements, fn
      str when is_binary(str) -> str in @pursuit_states
      atom when is_atom(atom) -> atom in @pursuit_state_atoms
      _ -> false
    end)
  end

  defp inspect_value(s) when is_binary(s), do: ~s("#{s}")
  defp inspect_value(a) when is_atom(a), do: inspect(a)
  defp inspect_value(other), do: inspect(other)

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Inline list of pursuit-state values — use a bucket from " <>
          "`MediaCentarr.Acquisition.Pursuits.State` (`in_flight/0`, `terminal/0`) " <>
          "so adding a new state only requires editing one file.",
      trigger: trigger,
      line_no: line_no || 1
    )
  end
end
