defmodule MediaCentaur.Credo.Checks.LookupNamingContract do
  use Credo.Check,
    id: "MC0022",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      A public lookup's name announces what it returns. The contract:

          fetch…   -> {:ok, record} | {:error, :not_found}
          get…     -> record | nil
          …!       -> the record, or raises

      Reading `fetch_thing(id)` should tell you to pattern-match a tuple
      without opening the module. When the name and the return shape
      disagree, every call site pays for the lie — and the mismatch spreads,
      because the next lookup is written to match its neighbour.

          # NOT preferred — named fetch_*, returns nil
          def fetch_for_extra(extra_id), do: Repo.get_by(ExtraProgress, extra_id: extra_id)

          # NOT preferred — named get_*, returns a tuple
          def get_pending_file(id) do
            case Repo.get(PendingFile, id) do
              nil -> {:error, :not_found}
              file -> {:ok, file}
            end
          end

          # preferred
          def fetch_for_extra(extra_id) do
            case Repo.get_by(ExtraProgress, extra_id: extra_id) do
              nil -> {:error, :not_found}
              record -> {:ok, record}
            end
          end

          def get_item(id), do: Repo.get(Item, id)

      The check only opines where the return shape is *statically*
      determinable — a tail call to a known nil-returning lookup
      (`Repo.get/2`, `Repo.get_by/2`, `Repo.one/1`, `Map.get/2`,
      `Enum.find/2`), or a `case`/`with` with both `{:ok, _}` and
      `{:error, _}` branches. Anything else is left alone, so HTTP clients
      (`TMDB.Client.get_movie/2`), GenServer readers
      (`Console.Buffer.get_filter/1`), and cache-then-database reads
      (`Settings.get_by_key/1`) are not second-guessed. That is deliberate:
      the check is scoped to repository-style lookups, where the convention
      actually holds.

      Public functions in `lib/` only — private helpers and test support are
      not part of the contract.

      **Plural `fetch_*` readers are out of scope by design.**
      `fetch_pending_groups/0`, `fetch_all_typed_entries/1`, and
      `fetch_recent_changes/0` return collections, not lookups: "none found"
      is `[]`, not `{:error, :not_found}`, so there is no tuple for the
      caller to match and nothing for the name to lie about. The contract
      governs *singular* record lookups. A singular `fetch_*` that returns a
      struct or a collection is the real smell — name it `load_*` or
      `build_*` — but that shape is not statically distinguishable from a
      plural reader here, so it stays a review concern rather than a check.

      Source: the 2026-08 audit-remediation campaign, Stage 4 (campaign
      retired; see git history).
      """
    ]

  # Calls that yield the record or `nil`.
  @nilable_calls [
    {:Repo, :get},
    {:Repo, :get_by},
    {:Repo, :one},
    {:Map, :get},
    {:Enum, :find}
  ]

  @lookup_name ~r/^(fetch|get)(_[a-z0-9_]+)?!?$/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if contract_path?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  # The naming contract governs the public surface of the application only.
  defp contract_path?(filename), do: String.starts_with?(filename, "lib/")

  defp traverse({:def, _meta, [head, body_parts]} = ast, issues, issue_meta) when is_list(body_parts) do
    case issue_for_definition(head, body_parts, issue_meta) do
      nil -> {ast, issues}
      issue -> {ast, [issue | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for_definition(head, body_parts, issue_meta) do
    with {name, line_no} <- function_name(head),
         name_str = Atom.to_string(name),
         true <- Regex.match?(@lookup_name, name_str),
         body when not is_nil(body) <- Keyword.get(body_parts, :do) do
      violation(name_str, shape(tail(body)), line_no, issue_meta)
    else
      _ -> nil
    end
  end

  defp function_name({:when, _meta, [inner | _guard]}), do: function_name(inner)
  defp function_name({name, meta, _args}) when is_atom(name), do: {name, meta[:line]}
  defp function_name(_), do: nil

  defp violation(name, :nilable, line_no, issue_meta) do
    cond do
      String.ends_with?(name, "!") ->
        issue_for(
          issue_meta,
          name,
          line_no,
          "`#{name}` ends in `!` but returns `nil` when the record is absent. " <>
            "A `!` lookup must raise — use `Repo.get!/2` — or drop the `!`."
        )

      String.starts_with?(name, "fetch") ->
        issue_for(
          issue_meta,
          name,
          line_no,
          "`#{name}` is named `fetch_*` but returns `nil` when the record is absent. " <>
            "Return `{:ok, record} | {:error, :not_found}`, or rename it to `get_*`."
        )

      true ->
        nil
    end
  end

  defp violation(name, :tuple, line_no, issue_meta) do
    if String.starts_with?(name, "get") and not String.ends_with?(name, "!") do
      issue_for(
        issue_meta,
        name,
        line_no,
        "`#{name}` is named `get_*` but returns an `{:ok, _} | {:error, _}` tuple. " <>
          "Rename it to `fetch#{String.replace_prefix(name, "get", "")}`, " <>
          "or return the record or `nil`."
      )
    end
  end

  defp violation(_name, :unknown, _line_no, _issue_meta), do: nil

  # The value a body evaluates to: the last statement of a block, or the
  # expression itself for a `do:` one-liner.
  defp tail({:__block__, _meta, statements}) when statements != [],
    do: statements |> List.last() |> tail()

  defp tail(expression), do: expression

  defp shape({:ok, _value}), do: :tuple
  defp shape({:error, _reason}), do: :tuple

  defp shape({:case, _meta, [_subject, clauses]}) when is_list(clauses),
    do: clauses |> Keyword.get(:do) |> branch_shape()

  defp shape({:with, _meta, arguments}) do
    case List.last(arguments) do
      parts when is_list(parts) -> parts |> Keyword.get(:do) |> tail_shape()
      _ -> :unknown
    end
  end

  defp shape({{:., _meta, [{:__aliases__, _alias_meta, parts}, function]}, _call_meta, _args}) do
    if {List.last(parts), function} in @nilable_calls, do: :nilable, else: :unknown
  end

  defp shape(_expression), do: :unknown

  defp tail_shape(nil), do: :unknown
  defp tail_shape(body), do: body |> tail() |> shape()

  # A `case` reads as a lookup result when one branch yields `{:ok, _}` and
  # another yields `{:error, _}`.
  defp branch_shape(clauses) when is_list(clauses) do
    kinds =
      Enum.map(clauses, fn
        {:->, _meta, [_pattern, body]} -> body |> tail() |> branch_kind()
        _ -> :other
      end)

    if :ok_tuple in kinds and :error_tuple in kinds, do: :tuple, else: :unknown
  end

  defp branch_shape(_clauses), do: :unknown

  defp branch_kind({:ok, _value}), do: :ok_tuple
  defp branch_kind({:error, _reason}), do: :error_tuple
  defp branch_kind(_expression), do: :other

  defp issue_for(issue_meta, trigger, line_no, message) do
    format_issue(issue_meta, message: message, trigger: trigger, line_no: line_no)
  end
end
