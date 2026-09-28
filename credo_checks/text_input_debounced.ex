defmodule MediaCentaur.Credo.Checks.TextInputDebounced do
  use Credo.Check,
    id: "MC0040",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A text field that sends change events must rate-limit them itself:
      `phx-debounce` (a delay, or `"blur"`) or `phx-throttle` on the field.

      Every keystroke in an undebounced field is a round trip, and the
      handler behind it is rarely free — a SQL query, a `Repo.all`, a
      filesystem probe, a stream reset. `phx-debounce` is the one
      mechanism: no hand-rolled `Process.send_after` debounce on the
      server, where every keystroke would still arrive.

      LiveView reads `phx-debounce` from the **input**, not the form, so a
      debounce written on a `<form phx-change>` rate-limits nothing:

          # BAD — every keystroke is an event
          <form phx-change="set_title" phx-debounce="300">
            <input type="text" name="value" />
          </form>

          # GOOD
          <form phx-change="set_title">
            <input type="text" name="value" phx-debounce="300" />
          </form>

      Checked: a raw `<textarea>`, or an `<input>` whose type is text-like
      (text — also no type — search, email, url, tel, password, number,
      range), that is inside a `<form phx-change>` or carries its own
      `phx-change` / `phx-keyup`. Discrete controls (checkbox, radio,
      hidden, select) send one event per act and are not checked. The input
      components `<.input>` and `<.settings_input>` are checked like the
      element they render; other components are not seen through.

      Source: the ui-state-ownership campaign (four undebounced fields, one
      of them a `Repo.all` per keystroke).
      """
    ]

  @text_like ~w(text search email url tel password number range)
  # The two input components are checked like the element they render.
  @tag_start ~r/<(\/?)(form|input|textarea|\.input|\.settings_input)\b/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if template_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      source = SourceFile.source(source_file)

      source
      |> tags()
      |> offending(source)
      |> Enum.map(&issue_for(issue_meta, &1))
    else
      []
    end
  end

  defp template_file?(filename) do
    String.contains?(filename, "lib/media_centaur_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex"))
  end

  # Every form/input/textarea tag in document order: `{kind, closing?,
  # text, offset}`, where `text` is the whole opening tag.
  defp tags(source) do
    @tag_start
    |> Regex.scan(source, return: :index, capture: :all)
    |> Enum.map(fn [{offset, _length}, slash, {name_offset, name_length}] ->
      name = binary_part(source, name_offset, name_length)
      closing? = slash != {-1, 0} and elem(slash, 1) > 0
      {name, closing?, tag_text(source, offset), offset}
    end)
  end

  # The opening tag up to its `>`, skipping any `>` inside a `{...}`
  # expression (`|>`) or a quoted attribute value.
  defp tag_text(source, offset) do
    rest = binary_part(source, offset, byte_size(source) - offset)
    scan_tag(rest, 0, nil, [])
  end

  defp scan_tag(<<>>, _depth, _quote, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp scan_tag(<<char, rest::binary>>, depth, quote, acc) do
    acc = [char | acc]

    cond do
      quote != nil and char == quote -> scan_tag(rest, depth, nil, acc)
      quote != nil -> scan_tag(rest, depth, quote, acc)
      char in [?", ?'] and depth == 0 -> scan_tag(rest, depth, char, acc)
      char == ?{ -> scan_tag(rest, depth + 1, nil, acc)
      char == ?} -> scan_tag(rest, max(depth - 1, 0), nil, acc)
      char == ?> and depth == 0 -> acc |> Enum.reverse() |> IO.iodata_to_binary()
      true -> scan_tag(rest, depth, nil, acc)
    end
  end

  defp offending(tags, source) do
    {offenders, _forms} =
      Enum.reduce(tags, {[], []}, fn
        {"form", true, _text, _offset}, {acc, [_ | forms]} ->
          {acc, forms}

        {"form", true, _text, _offset}, {acc, []} ->
          {acc, []}

        {"form", false, text, _offset}, {acc, forms} ->
          {acc, [changes?(text) | forms]}

        {_field, true, _text, _offset}, state ->
          state

        {field, false, text, offset}, {acc, forms} ->
          in_change? = Enum.any?(forms) or changes?(text) or text =~ ~r/phx-keyup\s*=/

          if in_change? and text_like?(field, text) and not rate_limited?(text) do
            {[line_of(source, offset) | acc], forms}
          else
            {acc, forms}
          end
      end)

    Enum.reverse(offenders)
  end

  defp changes?(text), do: text =~ ~r/phx-change\s*=/
  defp rate_limited?(text), do: text =~ ~r/phx-(debounce|throttle)\s*=/

  defp text_like?("textarea", _text), do: true

  defp text_like?(_input, text) do
    case Regex.run(~r/\btype\s*=\s*"([a-z]+)"/, text) do
      [_, type] -> type in @text_like
      nil -> not (text =~ ~r/\btype\s*=/)
    end
  end

  defp line_of(source, offset), do: source |> binary_part(0, offset) |> String.split("\n") |> length()

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "A text field that sends change events must carry its own `phx-debounce` " <>
          "(or `phx-throttle`); LiveView ignores one on the form. " <>
          "See MediaCentaur.Credo.Checks.TextInputDebounced.",
      trigger: "phx-change",
      line_no: line_no
    )
  end
end
