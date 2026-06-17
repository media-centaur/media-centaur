defmodule MediaCentaur.Credo.Checks.NoPhxValueValue do
  use Credo.Check,
    id: "MC0021",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      `phx-value-value` collides with the native `value` DOM property of
      form-associated elements (`<button>`, `<input>`). On click LiveView
      merges the element's own `value` into the event payload; a `<button>`
      with no `value` attribute reports `""`, which clobbers your
      `phx-value-value` — the handler receives `%{"value" => ""}` and the
      control silently does nothing.

      Insidiously, the render looks correct AND a `render_click/3` LiveViewTest
      passes: `render_click` reads the attribute straight off the DOM and never
      simulates the browser's native-value merge. So the bug ships green and
      only surfaces on a real click in a real browser. Use a descriptively
      named key instead:

          # BAD — clobbered to "" on a <button>
          <button phx-click="pick" phx-value-value={v}>…</button>
          def handle_event("pick", %{"value" => v}, socket)

          # GOOD
          <button phx-click="pick" phx-value-choice={v}>…</button>
          def handle_event("pick", %{"choice" => v}, socket)

      (`phx-value-name` does NOT collide — LiveView injects the native `value`,
      not `name` — so descriptive keys like `phx-value-choice`, `phx-value-id`
      are all fine. Only the literal key `value` is the trap.)

      Source: the interface-scale picker regression (`settings_choice`).
      """
    ]

  @phx_value_value ~r/phx-value-value\s*=/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if template_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        if Regex.match?(@phx_value_value, line) do
          [issue_for(issue_meta, line_no)]
        else
          []
        end
      end)
    else
      []
    end
  end

  defp template_file?(filename) do
    String.contains?(filename, "lib/media_centaur_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex"))
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "`phx-value-value` collides with a form element's native `value` " <>
          "property and is clobbered to \"\" on click. Use a descriptive key " <>
          "(e.g. `phx-value-choice`). See MediaCentaur.Credo.Checks.NoPhxValueValue.",
      trigger: "phx-value-value=",
      line_no: line_no
    )
  end
end
