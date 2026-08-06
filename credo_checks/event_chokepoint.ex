defmodule MediaCentaur.Credo.Checks.EventChokepoint do
  @moduledoc """
  Shared AST matcher for the typed-event chokepoint checks — MC0012
  (`playback:events`), MC0013 (`library:updates`) and MC0026
  (`review:updates`).

  Each of those checks asks the same question: *does this file publish one
  of my topic's tagged messages without going through the context's
  `Events.broadcast/1`?* Only the tag list and the exempt file differ, so
  the matching lives here.

  ## Why this module exists

  MC0012 and MC0013 each hand-rolled the match, and both got it wrong in
  the same way: they matched a payload of `{tag, _, _}`, which is a
  **three**-element AST node — an unquoted function call, or a 3+-element
  tuple literal via `{:{}, _, [tag | _]}`. A two-element tuple literal
  such as `{:entities_changed, event}` quotes to the plain 2-tuple
  `{:entities_changed, {:event, _, nil}}` and matches neither clause.

  Since `:entities_changed` is the *only* tag MC0013 guards, and every
  current playback payload is likewise a 2-tuple, both checks reported
  zero issues against a genuine violation from the day they were written.
  They were verified vacuous by running them against a hand-written
  violation, and this module is the fix.

  ## What counts as a publication

  Both spellings, so the check keeps working either side of ADR-060's
  transport migration:

      Topics.publish(Topics.review_updates(), {:file_added, event})
      Phoenix.PubSub.broadcast(MediaCentaur.PubSub, topic, {:file_added, event})

  and both payload arities:

      {:entities_changed, event}          # 2-tuple literal
      {:group_error, key, message}        # 3+-tuple literal
  """

  @doc """
  Returns `[{tag, line}]` for every publication in `source_file` of a
  message tagged with one of `tags`.

  Order is source order. A payload the matcher cannot read statically (a
  bare variable, a function call) is skipped rather than guessed at.
  """
  @spec publications(Credo.SourceFile.t(), [atom()]) :: [{atom(), pos_integer()}]
  def publications(source_file, tags) do
    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, tags), [])
    |> Enum.reverse()
  end

  @doc """
  True when `filename` should be skipped: the chokepoint module itself, or
  any test file (tests construct payloads to assert on them).
  """
  @spec exempt?(String.t(), String.t()) :: boolean()
  def exempt?(filename, chokepoint_path) do
    String.contains?(filename, chokepoint_path) or
      String.starts_with?(filename, "test/") or
      String.contains?(filename, "/test/")
  end

  # Topics.publish(topic, payload) — any alias ending in Topics
  defp traverse({{:., _, [{:__aliases__, _, mod}, :publish]}, meta, [_topic, payload]} = ast, acc, tags) do
    {ast, collect(payload, meta, acc, tags, List.last(mod) == :Topics)}
  end

  # Phoenix.PubSub.broadcast(server, topic, payload)
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Phoenix, :PubSub]}, :broadcast]}, meta,
          [_server, _topic, payload]} = ast,
         acc,
         tags
       ) do
    {ast, collect(payload, meta, acc, tags, true)}
  end

  defp traverse(ast, acc, _tags), do: {ast, acc}

  defp collect(payload, meta, acc, tags, true) do
    tag = tag_of(payload)

    if tag in tags do
      [{tag, meta[:line] || 0} | acc]
    else
      acc
    end
  end

  defp collect(_payload, _meta, acc, _tags, false), do: acc

  # `{:tag, value}` — a two-element tuple literal quotes to itself
  defp tag_of({tag, _value}) when is_atom(tag), do: tag

  # `{:tag, a, b, …}` — three-or-more-element tuple literals quote to `{:{}, _, [...]}`
  defp tag_of({:{}, _meta, [tag | _rest]}) when is_atom(tag), do: tag

  defp tag_of(_other), do: nil
end
