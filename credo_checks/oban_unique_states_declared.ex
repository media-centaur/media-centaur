defmodule MediaCentaur.Credo.Checks.ObanUniqueStatesDeclared do
  use Credo.Check,
    id: "MC0041",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      An Oban worker that declares `unique:` must name its `states:`.

      Oban's default unique states (`:successful`) include `completed`, so
      a job inserted while a finished one with the same keys is inside the
      period is silently not inserted. For a job that carries a decision
      or backs a pending row, that leaves the row with no job behind it —
      it happened to `RunPlan` (a replan soon after a plan solved) and
      `PursueTarget` (a re-arm soon after the last pursuit), and no test
      saw it, because inline test mode skips uniqueness.

      The check prescribes no value; it makes the choice visible:

          # a double click collapses into the waiting job; a request after
          # the last one started or finished always runs (ADR-077, rule 6)
          unique: [keys: [:plan_id], period: :infinity, states: [:available, :scheduled, :retryable]]

          # repeats within the period are deliberately suppressed, finished
          # jobs included
          unique: [keys: [:entity_id], period: 60, states: :successful]

      Source: ADR-077 rule 6; campaign `durable-work` finding F13.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:use, meta, [{:__aliases__, _, [:Oban, :Worker]}, options]} = ast, issues, issue_meta)
       when is_list(options) do
    case Keyword.get(options, :unique) do
      unique when is_list(unique) ->
        if Keyword.has_key?(unique, :states),
          do: {ast, issues},
          else: {ast, [issue_for(issue_meta, meta[:line]) | issues]}

      _none ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "An Oban worker's `unique:` must name its `states:` — the default counts completed jobs " <>
          "and silently drops a new one (ADR-077, rule 6).",
      trigger: "unique",
      line_no: line_no
    )
  end
end
