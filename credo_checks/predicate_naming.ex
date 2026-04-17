defmodule MediaCentarr.Credo.Checks.PredicateNaming do
  use Credo.Check,
    id: "MC0001",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Predicate functions in this codebase must end in `?` and must NOT start
      with `is_`. The `is_` prefix is reserved for guard-safe macros
      (`defmacro`, `defguard`, `defguardp`) where Elixir convention requires it.

          # preferred
          def user?(cookie), do: cookie != nil
          defp has_attachment?(mail), do: mail.attachments != []
          defguard is_user_id(value) when is_integer(value) and value > 0

          # NOT preferred
          def is_user(cookie), do: cookie != nil
          def is_user?(cookie), do: cookie != nil

      Source: AGENTS.md "Predicate Functions" rule.
      """
    ]

  @def_ops [:def, :defp]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  for op <- @def_ops do
    defp traverse({unquote(op), _meta, [{name, meta, _args} | _]} = ast, issues, issue_meta)
         when is_atom(name) do
      name_str = Atom.to_string(name)

      if String.starts_with?(name_str, "is_") do
        {ast, [issue_for(issue_meta, name_str, meta[:line]) | issues]}
      else
        {ast, issues}
      end
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, name, line_no) do
    format_issue(
      issue_meta,
      message:
        "Predicate functions must not start with `is_` (use a `?` suffix instead). " <>
          "Reserve `is_` for guard-safe macros — see AGENTS.md.",
      trigger: name,
      line_no: line_no
    )
  end
end
