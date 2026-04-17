defmodule MediaCentarr.Credo.Checks.LogMacroPreferred do
  use Credo.Check,
    id: "MC0005",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Code under `lib/media_centarr/` must log via the `MediaCentarr.Log`
      macros (`Log.info/2`, `Log.warning/2`, `Log.error/2`) rather than
      calling `Logger` directly. The Log macros tag every entry with a
      component, which the Console drawer uses for filtering.

          # preferred
          require MediaCentarr.Log, as: Log
          Log.info(:pipeline, "claimed 3 files")

          # NOT preferred
          require Logger
          Logger.info("claimed 3 files")

      Phoenix integration code under `lib/media_centarr_web/` may call
      `Logger` directly. The `MediaCentarr.Log` module itself is also
      exempt (it wraps `Logger`).

      Source: CLAUDE.md "Thinking Logs".
      """
    ]

  @forbidden_levels [:debug, :info, :warning, :error, :notice, :critical, :alert, :emergency]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp applies_to?(filename) do
    # The Console subsystem owns the buffer that backs the Log macros.
    # If Console.Buffer's persist fails, calling Log.warning would recurse
    # into the same broken buffer. Console.* is allowed to use Logger
    # directly with `mc_log_source: :buffer` to bypass the buffer.
    String.contains?(filename, "lib/media_centarr/") and
      not String.contains?(filename, "lib/media_centarr_web/") and
      not String.ends_with?(filename, "lib/media_centarr/log.ex") and
      not String.contains?(filename, "lib/media_centarr/console/")
  end

  defp traverse({{:., meta, [{:__aliases__, _, [:Logger]}, fun]}, _, _args} = ast, issues, issue_meta)
       when fun in @forbidden_levels do
    {ast, [issue_for(issue_meta, "Logger.#{fun}", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Use `MediaCentarr.Log` macros (e.g. `Log.info(:component, msg)`) instead of `#{trigger}` " <>
          "in lib/media_centarr/. See CLAUDE.md \"Thinking Logs\".",
      trigger: trigger,
      line_no: line_no
    )
  end
end
