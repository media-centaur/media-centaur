defmodule MediaCentaur.Credo.Checks.ModalBackdropViaComponent do
  use Credo.Check,
    id: "MC0020",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      The `modal-backdrop` class may only appear in the modal seam,
      `MediaCentaurWeb.Components.Modal` (`lib/.../components/modal.ex`).

      Every modal must go through the `<.modal>` component so the
      ephemeral-vs-persistent dismissal behavior is declared once via the
      required `dismiss` attr and can never be half-wired (a backdrop that
      forgets its click handler, an Escape binding without a backdrop one).

          # correct
          <.modal id="x" open={@open} dismiss={:ephemeral} on_close="close_x">
            ...panel content...
          </.modal>

          # NOT allowed — hand-rolled backdrop outside the seam
          <div class="modal-backdrop" phx-click={@on_close}>
            <div class="modal-panel">...</div>
          </div>
      """
    ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if allowed?(filename) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        if String.contains?(line, "modal-backdrop") do
          [issue_for(issue_meta, line_no)]
        else
          []
        end
      end)
    end
  end

  # The seam itself owns the class. The two credo-check test files carry
  # heredoc fixtures that intentionally include the literal we flag.
  defp allowed?(filename) do
    String.ends_with?(filename, "components/modal.ex") or
      String.ends_with?(filename, "modal_backdrop_via_component_test.exs") or
      String.ends_with?(filename, "modal_panel_no_click_away_test.exs")
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "`modal-backdrop` may only be used in the `<.modal>` seam " <>
          "(components/modal.ex) — route this modal through `<.modal>`.",
      trigger: "modal-backdrop",
      line_no: line_no
    )
  end
end
