defmodule MediaCentarr.Credo.Checks.ModalPanelNoClickAway do
  use Credo.Check,
    id: "MC0006",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Elements with the `modal-panel` class must not use `phx-click-away`
      for dismissal. `phx-click-away` installs a document-scoped listener
      that fires on any click outside the element's DOM subtree — which
      includes clicks inside sibling overlays (the Console drawer, a
      future toast, a popover). Those unrelated clicks silently dismiss
      the modal.

      Dismiss on backdrop click instead. The `modal-backdrop` is a
      full-viewport `position: fixed` element that semantically is
      "the area outside the modal"; higher-z-index overlays block clicks
      from reaching it via the browser's own hit-testing.

          # preferred
          <div class="modal-backdrop" phx-click={@on_close}>
            <div class="modal-panel" phx-click={%Phoenix.LiveView.JS{}}>
              ...
            </div>
          </div>

          # NOT preferred
          <div class="modal-backdrop">
            <div class="modal-panel" phx-click-away={@on_close}>
              ...
            </div>
          </div>
      """
    ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if self_test?(filename) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        if String.contains?(line, "modal-panel") and String.contains?(line, "phx-click-away") do
          [issue_for(issue_meta, line_no)]
        else
          []
        end
      end)
    end
  end

  # Test files for this check contain heredoc fixtures that intentionally
  # include the exact pattern we're flagging. Skip them.
  defp self_test?(filename) do
    String.ends_with?(filename, "modal_panel_no_click_away_test.exs")
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Elements with `modal-panel` must not use `phx-click-away`. " <>
          "Put `phx-click` on the `modal-backdrop` instead — see the check explanation.",
      trigger: "phx-click-away",
      line_no: line_no
    )
  end
end
