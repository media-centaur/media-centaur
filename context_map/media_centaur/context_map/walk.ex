defmodule MediaCentaur.ContextMap.Walk do
  @moduledoc """
  Turns a parsed source into a flat list of *mentions* — every atom used
  as a map/keyword key, as a bare literal value, or as a dot access —
  each with its line and whether it sits in a pattern (a `def` head, the
  left of `=`, the head of a `->` clause). The rules read mentions, never
  the AST.

  A key is the left side of a keyword pair (`rung:`, including `do`/`end`
  blocks) or of a map `=>` pair; the first element of a two-element tuple
  literal (`{:ok, value}`) is a value, not a key.

  A pattern is a definition head (`def`, `defp`, `defmacro`, `defmacrop`,
  `defguard`, `defguardp`; a `when` guard is not part of the pattern), the
  left of `=` or `<-`, or the head of a `->` clause. `cond` conditions are
  `->` heads and so count as patterns.

  `~H` templates are strings to the parser; they are scanned by regex for
  `:atom` values and `.field` accesses and marked `template?: true`.
  """

  alias MediaCentaur.ContextMap.Source

  @definitions [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]

  @type mention :: %{
          kind: :key | :value | :dot,
          atom: atom(),
          line: pos_integer(),
          pattern?: boolean(),
          template?: boolean()
        }

  @doc "Every mention in `source`, sorted by line, kind and atom."
  @spec mentions(Source.t()) :: [mention()]
  def mentions(%Source{ast: ast}) do
    {_, {mentions, _depth}} = Macro.traverse(ast, {[], 0}, &pre/2, &post/2)
    mentions |> Enum.reverse() |> Enum.sort_by(&{&1.line, &1.kind, &1.atom})
  end

  # --- pattern tracking: wrap pattern positions so entering them bumps the depth ---

  defp pre({definition, meta, [{:when, when_meta, [{name, head_meta, args}, guard]} | body]}, acc)
       when definition in @definitions and is_list(args),
       do:
         {{definition, meta, [{:when, when_meta, [{name, head_meta, [wrap(args)]}, guard]} | body]}, acc}

  defp pre({definition, meta, [{name, head_meta, args} | body]}, acc)
       when definition in @definitions and is_list(args),
       do: {{definition, meta, [{name, head_meta, [wrap(args)]} | body]}, acc}

  defp pre({:=, meta, [left, right]}, acc), do: {{:=, meta, [wrap(left), right]}, acc}
  defp pre({:<-, meta, [left, right]}, acc), do: {{:<-, meta, [wrap(left), right]}, acc}
  defp pre({:->, meta, [args, body]}, acc), do: {{:->, meta, [wrap(args), body]}, acc}
  defp pre({:__pattern__, _, [_]} = node, {mentions, depth}), do: {node, {mentions, depth + 1}}

  # sigil_H: the template is a string; scan it
  defp pre({:sigil_H, meta, [{:<<>>, _, [template]} | _]} = node, {mentions, depth})
       when is_binary(template),
       do: {node, {template_mentions(template, template_start_line(meta)) ++ mentions, depth}}

  # a two-element tuple literal: Sourceror wraps it in __block__; its
  # elements are values, so it is re-shaped as a `{:{}, ...}` tuple node
  defp pre({:__block__, meta, [{left, right}]}, acc), do: {{:{}, meta, [left, right]}, acc}

  # keyword / map pair (tuple literals are re-shaped above, so every
  # remaining 2-tuple is a pair): the key is a key mention, and must not be
  # re-walked as a value
  defp pre({{:__block__, meta, [key]}, value}, {mentions, depth}) when is_atom(key),
    do: {{nil, value}, {[mention(:key, key, meta, depth) | mentions], depth}}

  # dot access: x.field / i.field / @assigns.field
  defp pre({{:., meta, [_subject, field]}, _, []} = node, {mentions, depth}) when is_atom(field),
    do: {node, {[mention(:dot, field, meta, depth) | mentions], depth}}

  # bare atom literal (Sourceror wraps literals in __block__)
  defp pre({:__block__, meta, [atom]} = node, {mentions, depth})
       when is_atom(atom) and not is_boolean(atom) and not is_nil(atom),
       do: {node, {[mention(:value, atom, meta, depth) | mentions], depth}}

  defp pre(node, acc), do: {node, acc}

  defp post({:__pattern__, _, [_]} = node, {mentions, depth}), do: {node, {mentions, depth - 1}}
  defp post(node, acc), do: {node, acc}

  defp wrap(inner), do: {:__pattern__, [], [inner]}

  defp mention(kind, atom, meta, depth),
    do: %{
      kind: kind,
      atom: atom,
      line: Keyword.get(meta, :line, 1),
      pattern?: depth > 0,
      template?: false
    }

  # --- templates ---

  # A heredoc sigil's content starts on the line after the opening `"""`;
  # a single-line sigil's content starts on the sigil's own line.
  defp template_start_line(meta) do
    line = Keyword.get(meta, :line, 1)
    if meta[:delimiter] in [~s("""), "'''"], do: line + 1, else: line
  end

  defp template_mentions(template, start_line) do
    template
    |> String.split("\n")
    |> Enum.with_index(start_line)
    |> Enum.flat_map(fn {text, line} ->
      values =
        for [_, atom] <- Regex.scan(~r/(?<![\w@:\]])\:([a-z_][a-z0-9_?!]*)/, text),
            do: template_mention(:value, atom, line)

      # a dot chain (`@entity.meta.status`, `f(x).field`) is matched whole and
      # split, so every field is found; the anchor is a lowercase identifier
      # or a closing bracket, so `Alias.fun` is not a dot access
      dots =
        for [_, chain] <- Regex.scan(~r/(?:(?<=[\)\]])|\b[a-z_]\w*)((?:\.[a-z_][a-z0-9_?!]*)+)/, text),
            field <- String.split(chain, ".", trim: true),
            do: template_mention(:dot, field, line)

      values ++ dots
    end)
  end

  # Template names come from this repo's source files, a bounded set.
  defp template_mention(kind, name, line) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    %{kind: kind, atom: String.to_atom(name), line: line, pattern?: false, template?: true}
  end
end
