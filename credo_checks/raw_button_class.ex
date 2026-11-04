defmodule MediaCentaur.Credo.Checks.RawButtonClass do
  use Credo.Check,
    id: "MC0007",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Templates under `lib/media_centaur_web/` must not use raw daisyUI
      `btn` classes directly. Go through the `<.button>` component, which
      encodes the button variants (primary, secondary, action,
      info, risky, danger, dismiss, destructive_inline, neutral, outline)
      and sizes (xs, sm, md, lg).

          # preferred
          <.button variant="primary" size="lg" phx-click="play">Play</.button>
          <.button variant="dismiss" phx-click="cancel">Cancel</.button>

          # NOT preferred
          <button class="btn btn-primary btn-lg" phx-click="play">Play</button>
          <button class="btn btn-ghost" phx-click="cancel">Cancel</button>

      The list and expression forms are checked too — a string literal in
      `class={["join-item btn btn-xs", @state]}` is a raw button class.

      Extra utility classes are still fine — pass them via the `class`
      attribute on `<.button>`. Custom CSS classes that happen to end in
      `-btn` (e.g. `controls-icon-btn`, `hint-btn`) are not flagged; only
      the standalone daisyUI `btn` token triggers this check.

      The button component itself (`core_components.ex`) is exempt — it
      owns the literal `btn` string.

      Source: the `user-interface` skill (Buttons). This check and `button/1` are the spec.
      """
    ]

  # `class="..."` (string-form attribute value)
  @class_attr_string ~r/class\s*=\s*"([^"]*)"/

  # `class={...}` (expression-form attribute value: a list or a string
  # expression), possibly spread over several lines. Its string literals are
  # what can carry the token.
  @class_attr_expression ~r/class\s*=\s*\{([^}]*)\}/s
  @string_literal ~r/"([^"]*)"/

  # standalone `btn` token (whitespace-delimited or value-edge)
  @btn_token ~r/(?:^|\s)btn(?:\s|$)/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      source = SourceFile.source(source_file)

      (string_form_lines(source) ++ expression_form_lines(source))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&issue_for(issue_meta, &1))
    else
      []
    end
  end

  defp string_form_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_no} -> raw_btn_class?(line) end)
    |> Enum.map(fn {_line, line_no} -> line_no end)
  end

  # The line of each string literal inside a `class={...}` that carries the token.
  defp expression_form_lines(source) do
    @class_attr_expression
    |> Regex.scan(source, return: :index, capture: :all_but_first)
    |> Enum.flat_map(fn [{start, length}] ->
      expression = binary_part(source, start, length)

      @string_literal
      |> Regex.scan(expression, return: :index, capture: :all_but_first)
      |> Enum.filter(fn [{at, size}] -> Regex.match?(@btn_token, binary_part(expression, at, size)) end)
      |> Enum.map(fn [{at, _size}] -> line_of(source, start + at) end)
    end)
  end

  defp line_of(source, offset) do
    source |> binary_part(0, offset) |> String.split("\n") |> length()
  end

  defp applies_to?(filename) do
    template_file?(filename) and not exempt?(filename)
  end

  defp template_file?(filename) do
    String.contains?(filename, "lib/media_centaur_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex"))
  end

  # `core_components.ex` defines the `<.button>` component itself — it is
  # the only place allowed to write the literal `btn` class string.
  # The check's own test file contains heredoc fixtures that intentionally
  # include the flagged pattern; skip it.
  defp exempt?(filename) do
    String.ends_with?(filename, "core_components.ex") or
      String.ends_with?(filename, "raw_button_class_test.exs")
  end

  defp raw_btn_class?(line) do
    @class_attr_string
    |> Regex.scan(line, capture: :all_but_first)
    |> List.flatten()
    |> Enum.any?(&Regex.match?(@btn_token, &1))
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Use the `<.button>` component (with `variant` and `size`) instead of raw `btn` classes. " <>
          "See `MediaCentaurWeb.CoreComponents.button/1`.",
      trigger: "btn",
      line_no: line_no
    )
  end
end
