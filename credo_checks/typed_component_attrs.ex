defmodule MediaCentarr.Credo.Checks.TypedComponentAttrs do
  use Credo.Check,
    id: "MC0008",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Phoenix function-component `attr` declarations under
      `lib/media_centarr_web/` that use a loose type (`:list`, `:map`,
      `:any`, or `:global`) must carry a non-empty `doc:` justification.

          # preferred (typed)
          attr :items, :list, required: true, doc: "list of `Item.t()`"
          attr :entity, MediaCentarr.Library.Movie, required: true
          attr :delete_confirm, :any, default: nil, doc: "transient flag"

          # NOT preferred
          attr :items, :list, required: true
          attr :entity, :map, required: true

      The `doc:` field is the explicit waiver — it forces a contributor
      to document why a loose contract is acceptable instead of silently
      passing untyped data to a component. Per
      `~/src/media-centarr/component-contract-plan.md`, prefer in order:

        1. Co-located view-model struct with `@enforce_keys`
        2. Existing Ecto schema reference (`Library.Movie`, etc.)
        3. Shared `MediaCentarrWeb.ViewModels.*` struct
        4. `:list` / `:map` / `:any` / `:global` with a `doc:`
           justification (last resort)

      Phoenix's `attr` macro itself doesn't validate element types for
      `:list` / `:map`, so the contract has to be encoded another way —
      either a struct's `@enforce_keys` (preferred), or this prose
      waiver (acceptable for shapes that are genuinely heterogeneous,
      stream payloads, Earmark AST nodes, transient state flags).

      Source: CLAUDE.md / component-contract-plan.md.
      """
    ]

  @loose_types [:list, :map, :any, :global]

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
    String.contains?(filename, "lib/media_centarr_web/") and
      String.ends_with?(filename, ".ex")
  end

  # `attr :name, :type` — 2 args, no opts → loose type without doc is a violation.
  defp traverse({:attr, meta, [name, type]} = ast, issues, issue_meta)
       when is_atom(name) and is_atom(type) and type in @loose_types do
    {ast, [issue_for(issue_meta, Atom.to_string(name), meta[:line]) | issues]}
  end

  # `attr :name, :type, opts` — 3 args → loose type without `doc:` is a violation.
  defp traverse({:attr, meta, [name, type, opts]} = ast, issues, issue_meta)
       when is_atom(name) and is_atom(type) and type in @loose_types do
    if has_doc?(opts) do
      {ast, issues}
    else
      {ast, [issue_for(issue_meta, Atom.to_string(name), meta[:line]) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # The opts AST is a literal keyword list when the attr is written with
  # inline options. Each entry is `{key, value}` where the value is a
  # quoted form. We only count the `doc:` key as present when its value
  # is a non-empty binary or a string interpolation — `doc: ""` and
  # `doc: nil` are NOT valid waivers.
  defp has_doc?(opts) when is_list(opts) do
    Enum.any?(opts, fn
      {:doc, value} -> doc_value_present?(value)
      _ -> false
    end)
  end

  defp has_doc?(_), do: false

  defp doc_value_present?(binary) when is_binary(binary), do: String.trim(binary) != ""
  # String interpolation: `doc: "list of #{Module}.t()"` → AST is a
  # `:<<>>` sigil-like construct; treat as present.
  defp doc_value_present?({:<<>>, _, _}), do: true
  # Concatenation via `<>`: `doc: "foo " <> "bar"` → AST is `{:<>, _, [...]}`.
  defp doc_value_present?({:<>, _, _}), do: true
  defp doc_value_present?(_), do: false

  defp issue_for(issue_meta, name, line_no) do
    format_issue(
      issue_meta,
      message:
        "Component attr `#{name}` uses a loose type (`:list`/`:map`/`:any`/`:global`) " <>
          "without a `doc:` justification. Either tighten to a struct/schema or add " <>
          "`doc: \"<reason>\"`. See component-contract-plan.md.",
      trigger: name,
      line_no: line_no
    )
  end
end
