defmodule MediaCentaur.Credo.Checks.TestCaseTemplate do
  use Credo.Check,
    id: "MC0035",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Every test module states whether it owns the machine, through the
      suite's own case template.

          # preferred
          use MediaCentaur.Case, async: true       # pure — owns nothing global
          use MediaCentaur.Case, async: false      # checked out: global state is
                                                   # restored and verified around it
          use MediaCentaur.DataCase, async: false
          use MediaCentaurWeb.ConnCase, async: false

          # NOT preferred
          use ExUnit.Case, async: false            # never checked out — reads
                                                   # whatever the previous test left
          use MediaCentaur.Case                    # ownership left to a default

      `MediaCentaur.Case` is the edge `MediaCentaur.GlobalStateSandbox`
      needs: a sync test checks the machine out at entry and back in at
      exit. A bare `use ExUnit.Case` skips it, and a sync test that skips
      it reads state the previous test left behind — the class of failure
      that only shows up at some seeds.

      `async:` is always written, because it is the one statement of
      ownership and a default hides it. `Credo.Test.Case` is the one
      foreign template allowed: it is `async: true` by construction and a
      check test owns nothing global. Case templates under `test/support/`
      use `ExUnit.CaseTemplate` directly, as they must.

      Source: `campaigns/test-suite-determinism.md`.
      """
    ]

  @own_templates [
    [:MediaCentaur, :Case],
    [:MediaCentaur, :DataCase],
    [:MediaCentaurWeb, :ConnCase]
  ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if test_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_file?(filename), do: String.starts_with?(filename, "test/") and String.ends_with?(filename, "_test.exs")

  defp traverse({:use, meta, [{:__aliases__, _, [:ExUnit, :Case]} | _]} = ast, issues, issue_meta) do
    {ast, [bare_ex_unit(issue_meta, meta[:line]) | issues]}
  end

  defp traverse({:use, meta, [{:__aliases__, _, aliases} | opts]} = ast, issues, issue_meta)
       when aliases in @own_templates do
    if explicit_async?(opts) do
      {ast, issues}
    else
      {ast, [implicit_async(issue_meta, Enum.join(aliases, "."), meta[:line]) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp explicit_async?([opts]) when is_list(opts), do: Keyword.get(opts, :async) in [true, false]
  defp explicit_async?(_opts), do: false

  defp bare_ex_unit(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Test modules use `MediaCentaur.Case, async: true|false` (or DataCase / ConnCase), never `ExUnit.Case` " <>
          "directly — a sync test outside the template is never checked out of the global-state sandbox.",
      trigger: "ExUnit.Case",
      line_no: line_no
    )
  end

  defp implicit_async(issue_meta, template, line_no) do
    format_issue(
      issue_meta,
      message:
        "`use #{template}` states `async:` explicitly — it is the one declaration of whether " <>
          "this test owns the machine, and a default hides it.",
      trigger: template,
      line_no: line_no
    )
  end
end
