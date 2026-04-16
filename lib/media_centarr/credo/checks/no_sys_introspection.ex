defmodule MediaCentarr.Credo.Checks.NoSysIntrospection do
  use Credo.Check,
    id: "MC0004",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Tests must never use `:sys.get_state/1`, `:sys.replace_state/2`, or
      similar GenServer introspection. Test through the module's public API
      instead.

          # preferred — exercise public API
          MyServer.add(:foo)
          assert MyServer.count() == 1

          # NOT preferred
          state = :sys.get_state(MyServer)
          assert state.count == 0

      Source: ADR-026 (GenServer API encapsulation), CLAUDE.md "What We
      Never Test".
      """
    ]

  @forbidden [:get_state, :replace_state, :get_status, :statistics, :suspend, :resume]

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

  defp traverse({{:., meta, [:sys, fun]}, _, _args} = ast, issues, issue_meta) when fun in @forbidden do
    {ast, [issue_for(issue_meta, ":sys.#{fun}", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Tests must not use `#{trigger}`. " <>
          "Test through the module's public API — see ADR-026 and CLAUDE.md \"What We Never Test\".",
      trigger: trigger,
      line_no: line_no
    )
  end
end
