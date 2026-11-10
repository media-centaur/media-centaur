defmodule MediaCentaur.Credo.Checks.NoSupervisorChildToggling do
  use Credo.Check,
    id: "MC0045",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      A setting decides whether a child is *started*; no code stops a
      started child of a static Supervisor to express a setting, and
      `Supervisor.restart_child/2` is never a start path. Children that run
      while a flag is on are `MediaCentaur.FlagSupervisor`'s children, absent
      from the tree while it is off.

      Why: under `:rest_for_one` and `:one_for_all`, a sibling's restart
      starts a child that was stopped with `terminate_child/2` — the
      pipeline a user had turned off came back on when its Stats process
      crashed. A stopped child is also a second representation of the
      setting beside the flag, and the two drift.

          # preferred — the flag's children exist only while it is on
          {MediaCentaur.FlagSupervisor, flag: fn -> Services.start?(:start_pipeline) end, children: [...]}

          # NOT preferred
          Supervisor.terminate_child(__MODULE__, MediaCentaur.Pipeline.Import)
          Supervisor.restart_child(__MODULE__, MediaCentaur.Pipeline.Import)

      `DynamicSupervisor.terminate_child/2` is the normal way to end a
      dynamic child and is not what this check is about. A test may drive a
      supervisor it started.

      Source: campaign `supervision-tree.md`, ADR-081 (2026-11-10 amendment).
      """
    ]

  @forbidden [:terminate_child, :restart_child]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if String.starts_with?(filename, "lib/") or String.contains?(filename, "/lib/") do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp traverse({{:., meta, [{:__aliases__, _, [:Supervisor]}, fun]}, _, _args} = ast, issues, issue_meta)
       when fun in @forbidden do
    {ast, [issue_for(issue_meta, "Supervisor.#{fun}", meta[:line]) | issues]}
  end

  defp traverse({{:., meta, [:supervisor, fun]}, _, _args} = ast, issues, issue_meta) when fun in @forbidden do
    {ast, [issue_for(issue_meta, ":supervisor.#{fun}", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}` expresses a setting as a stopped child. " <>
          "Make the processes a `MediaCentaur.FlagSupervisor`'s children instead.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
