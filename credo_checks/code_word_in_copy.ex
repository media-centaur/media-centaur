defmodule MediaCentaur.Credo.Checks.CodeWordInCopy do
  use Credo.Check,
    id: "MC0044",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      User-facing copy never says "pursuit". The UI calls a download goal a
      *download*, the download client's item a *job*, and a release tried a
      *release* (decision of 2026-11-05, `campaigns/pursuit-window.md`);
      "pursuit" is the code's word and stays in identifiers, logs and
      contributor docs.

          # preferred
          <.button …>Cancel download</.button>
          put_flash(socket, :info, "Download started.")

          # NOT preferred
          <.button …>Cancel pursuit</.button>
          put_flash(socket, :info, "Pursuit started.")

      Checks string literals, heredocs and `~H` templates under
      `lib/media_centaur_web/` and every `view_models/` directory under
      `lib/media_centaur/`. Skipped: `@doc`, `@moduledoc`, `@typedoc`,
      `@storybook_reason`, `doc:` keyword values, `Log.*` messages and HEEx
      comments. A match is the word on its own — `select_pursuit`,
      `pursuit-modal` and `PursuitStyle` are identifiers and pass.

      **A rollout scaffold, not a standing rule.** It is the worklist and the
      guard while the pursuit-window campaign writes new copy; the campaign's
      closing commit removes it (owner's direction, 2026-11-05).
      """
    ]

  @code_word ~r/(?<![\w\-])pursuits?(?![\w\-])/i
  @heex_comment ~r/<%!--.*?--%>/s
  # `data-nav-zone="pursuits"`, `{@open && "pursuit"}`: a bare quoted word
  # is an identifier, never copy (copy is a sentence).
  @identifier_value ~r/["']pursuits?["']/i
  @doc_attributes [:doc, :moduledoc, :typedoc, :storybook_reason]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.to_tokens()
      |> string_tokens_in_copy()
      |> Enum.flat_map(&offending_lines/1)
      |> Enum.map(fn {line_no, trigger} ->
        format_issue(issue_meta,
          message: ~s{Copy says "pursuit"; the UI's word is "download" (a client's item is a "job").},
          trigger: trigger,
          line_no: line_no
        )
      end)
    else
      []
    end
  end

  defp applies_to?(filename) do
    String.ends_with?(filename, ".ex") and
      (String.contains?(filename, "lib/media_centaur_web/") or
         (String.contains?(filename, "lib/media_centaur/") and
            String.contains?(filename, "/view_models/")))
  end

  # Walks the token stream with the tokens before each string, so a doc
  # attribute, a `doc:` keyword or a `Log.` call can exempt it. A string
  # joined to an exempt one with `<>` inherits the exemption (a long
  # `doc:` split over lines). Line breaks are not context.
  defp string_tokens_in_copy(tokens) do
    tokens
    |> Enum.reject(&match?({:eol, _}, &1))
    |> Enum.with_index()
    |> Enum.reduce({[], false}, fn {token, index}, {copy, previous_exempt?} ->
      cond do
        not string_token?(token) ->
          {copy, previous_exempt?}

        exempt?(preceding(tokens, index), previous_exempt?) ->
          {copy, true}

        true ->
          {[token | copy], false}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp preceding(tokens, index) do
    tokens
    |> Enum.reject(&match?({:eol, _}, &1))
    |> Enum.slice(max(index - 6, 0), min(index, 6))
  end

  defp string_token?({:bin_string, _meta, _parts}), do: true
  defp string_token?({:bin_heredoc, _meta, _indent, _parts}), do: true
  defp string_token?({:sigil, _meta, :sigil_H, _parts, _mods, _indent, _delim}), do: true
  defp string_token?(_token), do: false

  defp exempt?(preceding, previous_exempt?) do
    doc_attribute?(preceding) or doc_keyword?(preceding) or log_call?(preceding) or
      (previous_exempt? and concatenation?(preceding))
  end

  defp concatenation?(preceding), do: match?([{:concat_op, _, :<>}], Enum.take(preceding, -1))

  defp doc_attribute?(preceding) do
    case Enum.take(preceding, -2) do
      [{:at_op, _, :@}, {:identifier, _, name}] -> name in @doc_attributes
      _other -> false
    end
  end

  defp doc_keyword?(preceding) do
    match?([{:kw_identifier, _, :doc}], Enum.take(preceding, -1))
  end

  defp log_call?(preceding), do: Enum.any?(preceding, &match?({:alias, _, :Log}, &1))

  defp offending_lines({:bin_string, {line, _col, _}, parts}), do: matches(text(parts), line)

  defp offending_lines({:bin_heredoc, {line, _col, _}, _indent, parts}),
    do: matches(text(parts), line + 1)

  defp offending_lines({:sigil, {line, _col, _}, :sigil_H, parts, _mods, _indent, _delim}) do
    parts
    |> text()
    |> blank_heex_comments()
    |> matches(line + 1)
  end

  defp text(parts), do: parts |> Enum.filter(&is_binary/1) |> Enum.join()

  # A bare quoted word is an identifier, not copy; dropped before the match.
  defp without_identifier_values(line), do: Regex.replace(@identifier_value, line, ~s(=""))

  # A comment is replaced by as many newlines as it spans, so the lines
  # after it keep their numbers.
  defp blank_heex_comments(content) do
    Regex.replace(@heex_comment, content, fn comment ->
      String.duplicate("\n", comment |> String.graphemes() |> Enum.count(&(&1 == "\n")))
    end)
  end

  defp matches(content, first_line) do
    content
    |> String.split("\n")
    |> Enum.with_index(first_line)
    |> Enum.filter(fn {line, _no} -> Regex.match?(@code_word, without_identifier_values(line)) end)
    |> Enum.map(fn {line, no} -> {no, String.trim(line)} end)
  end
end
