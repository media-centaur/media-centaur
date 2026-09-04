defmodule MediaCentaur.Credo.Checks.LogComponentMatchesContext do
  use Credo.Check,
    id: "MC0033",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      A `MediaCentaur.Log` call tags the component of the context that owns
      the code making it.

      The component tag answers one question for a reader of the Console
      drawer: *which part of the app said this?* When Acquisition,
      ReleaseTracking, Review and the image pipeline all tagged `:library`,
      filtering the drawer to `:library` returned four subsystems' output
      and filtering for those four returned nothing — the tag stopped
      carrying information. That is what this check prevents recurring: the
      2026-09 audit (E53) found ~23 such sites.

          # lib/media_centaur/review/intake.ex
          Log.info(:review, "claimed a file")   # correct
          Log.info(:library, "claimed a file")  # reported

      The mapping is `MediaCentaur.Log.Component`'s owning-context table,
      which this check reads directly rather than restating — one table, one
      answer. It is deliberately many-to-one: `downloads`, `search` and
      `release_tracking` all log as `:acquisition`, because getting a
      release is one subsystem to a reader whatever the module tree says.

      Two exemptions:

        * **The web layer.** A LiveView logs about the domain it displays,
          not about itself — `IncomingLive` tagging `:acquisition` is right.
        * **Unmapped contexts.** A context with no entry in the table has no
          required component and is left alone. Add it to the table to bring
          it under the rule.

      A non-literal component (`Log.info(component, …)`) is not checked;
      there is nothing to compare.

      Source: `MediaCentaur.Log.Component`, audit finding E53.
      """
    ]

  alias MediaCentaur.Log.Component

  @levels [:debug, :info, :warning, :error]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    case Component.for_context(Component.context_for_path(filename)) do
      nil ->
        []

      expected ->
        issue_meta = IssueMeta.for(source_file, params)
        Credo.Code.prewalk(source_file, &traverse(&1, &2, {issue_meta, expected}))
    end
  end

  defp traverse(
         {{:., meta, [{:__aliases__, _, alias_parts}, level]}, _, [tag | _rest]} = ast,
         issues,
         {issue_meta, expected}
       )
       when level in @levels and is_atom(tag) do
    if log_alias?(alias_parts) and tag != expected do
      {ast, [issue_for(issue_meta, meta[:line], tag, expected) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _acc), do: {ast, issues}

  # `Log.info(…)` via `require MediaCentaur.Log, as: Log`, and the fully
  # qualified `MediaCentaur.Log.info(…)`.
  defp log_alias?([:Log]), do: true
  defp log_alias?([:MediaCentaur, :Log]), do: true
  defp log_alias?(_), do: false

  defp issue_for(issue_meta, line_no, tag, expected) do
    format_issue(
      issue_meta,
      message:
        "This context logs as #{inspect(expected)}, not #{inspect(tag)}. A component tag " <>
          "names the context that owns the emitting code, so the Console drawer's filter " <>
          "means something. If #{inspect(tag)} is right, the context belongs under it in " <>
          "`MediaCentaur.Log.Component`.",
      trigger: inspect(tag),
      line_no: line_no
    )
  end
end
