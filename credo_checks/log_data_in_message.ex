defmodule MediaCentaur.Credo.Checks.LogDataInMessage do
  use Credo.Check,
    id: "MC0039",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A `MediaCentaur.Log` call puts its data in the message, not in the
      keyword list.

      The keyword list becomes `:logger` metadata, and nothing that shows a
      log line renders metadata: not the Console, not the journal
      formatter, not a Status incident. A reason passed as `reason:` is
      logged and then thrown away — the 2026-09-26 time series snapshot
      incident said "ignored" and nobody could tell why.

          Log.warning(:http, "snapshot ignored — \#{inspect(reason)}")   # correct
          Log.warning(:http, "snapshot ignored", reason: inspect(reason)) # reported

      The one key the diagnostics layer reads, `mc_incident:`, is allowed
      (see the `MediaCentaur.Log` moduledoc). A non-literal keyword list is
      not checked.
      """
    ]

  @levels [:debug, :info, :warning, :error]
  @allowed_keys [:mc_incident]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse(
         {{:., meta, [{:__aliases__, _, alias_parts}, level]}, _, [_component, _message, metadata]} = ast,
         issues,
         issue_meta
       )
       when level in @levels and is_list(metadata) do
    if log_alias?(alias_parts) do
      found =
        for {key, _value} <- metadata, is_atom(key), key not in @allowed_keys do
          issue_for(issue_meta, meta[:line], key)
        end

      {ast, found ++ issues}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp log_alias?([:Log]), do: true
  defp log_alias?([:MediaCentaur, :Log]), do: true
  defp log_alias?(_), do: false

  defp issue_for(issue_meta, line_no, key) do
    format_issue(
      issue_meta,
      message:
        "`#{key}:` becomes logger metadata, which no log view renders. " <>
          "Interpolate it into the message instead.",
      trigger: Atom.to_string(key),
      line_no: line_no
    )
  end
end
