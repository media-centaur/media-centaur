defmodule MediaCentarr.Credo.Checks.NoAbbreviatedNames do
  use Credo.Check,
    id: "MC0002",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Variable and parameter names must not be domain abbreviations that
      require mental expansion. Use full words: `file` not `wf`, `movie` not
      `e`, `episode` not `ep`, `season` not `s`, `result` not `res`.

      Universal Elixir/OTP idioms (`id`, `pid`, `ref`, `acc`, `fn`, `ok`,
      `msg`) are exempt. Underscore-prefixed unused variables (`_wf`) are
      also exempt.

          # preferred
          def process(file, movie, episode), do: ...

          # NOT preferred
          def process(wf, e, ep), do: ...

      Source: CLAUDE.md "Variable Naming" rule.
      """
    ]

  @denylist ~w(wf e ep s res wp ent)

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({op, _meta, [{_name, _, args} | _]} = ast, issues, issue_meta)
       when op in [:def, :defp] and is_list(args) do
    new_issues =
      args
      |> collect_param_names()
      |> Enum.filter(fn {name, _meta} -> Atom.to_string(name) in @denylist end)
      |> Enum.map(fn {name, meta} ->
        issue_for(issue_meta, Atom.to_string(name), meta[:line])
      end)

    {ast, new_issues ++ issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # Recursively walk parameter ASTs to extract bare variable names.
  defp collect_param_names(args) when is_list(args) do
    Enum.flat_map(args, &extract_var_names/1)
  end

  # Bare variable: `{name, meta, nil}` where name does not start with `_`.
  defp extract_var_names({name, meta, nil}) when is_atom(name) and not is_nil(name) do
    name_str = Atom.to_string(name)

    if String.starts_with?(name_str, "_") do
      []
    else
      [{name, meta}]
    end
  end

  # Pattern with binding: `{:=, _, [pattern, {name, meta, nil}]}`
  defp extract_var_names({:=, _meta, [left, right]}) do
    extract_var_names(left) ++ extract_var_names(right)
  end

  # Map / struct / tuple / list patterns — recurse into children.
  defp extract_var_names({_op, _meta, args}) when is_list(args) do
    Enum.flat_map(args, &extract_var_names/1)
  end

  defp extract_var_names({a, b}) do
    extract_var_names(a) ++ extract_var_names(b)
  end

  defp extract_var_names(list) when is_list(list) do
    Enum.flat_map(list, &extract_var_names/1)
  end

  defp extract_var_names(_), do: []

  defp issue_for(issue_meta, name, line_no) do
    format_issue(
      issue_meta,
      message:
        "Avoid abbreviated parameter name `#{name}`. " <>
          "Use a full word (e.g. `file`, `movie`, `episode`) — see CLAUDE.md \"Variable Naming\".",
      trigger: name,
      line_no: line_no
    )
  end
end
