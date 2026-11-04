defmodule MediaCentaur.Credo.Checks.DeviceNeutralConfirmCopy do
  use Credo.Check,
    id: "MC0043",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Confirmation copy in the web layer must not tell the user to click.
      Every page is driven by keyboard, TV remote and gamepad as much as by a
      mouse, and none of those click: an armed button's second-press label
      says "Press again to …".

          # preferred
          <.armed_button armed_label="Press again to remove" …>

          # NOT preferred
          <.armed_button armed_label="Click again to remove" …>

      Checks every line of `.ex` / `.heex` files under
      `lib/media_centaur_web/` for "click again" or "click to confirm",
      in any case.
      """
    ]

  @pointer_wording ~r/click (again|to confirm)/i

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.lines()
      |> Enum.filter(fn {_line_no, line} -> Regex.match?(@pointer_wording, line) end)
      |> Enum.map(fn {line_no, _line} ->
        format_issue(issue_meta,
          message:
            ~s{Confirmation copy says "click"; a remote or gamepad presses — write "Press again to …".},
          line_no: line_no
        )
      end)
    else
      []
    end
  end

  defp applies_to?(filename) do
    String.contains?(filename, "lib/media_centaur_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex"))
  end
end
