defmodule MediaCentaur.Credo.Checks.NativeConfirmDialog do
  use Credo.Check,
    id: "MC0027",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      `data-confirm` renders the browser's native `confirm()` dialog. It
      ignores the theme and it is not reachable with a d-pad — and this app is
      driven by a gamepad from a couch, so a confirmation the user cannot
      answer is worse than no confirmation at all.

      A destructive action picks one of three treatments, by consequence:

        * **Trivially reversible** (removing one row from a list the user can
          re-add) — **no confirmation.** A dialog on a cheap, undoable action
          trains people to dismiss dialogs. This is the default; earn the
          other two.

        * **Costly but recoverable** (work is lost, but only time) — the
          inline two-click gesture. The button itself arms and flips to
          "Click again to confirm". No overlay, already themed, already
          navigable.

              <.button phx-click="refresh" ...>
                {if @confirming, do: "Click again to confirm", else: "Refresh"}
              </.button>

        * **Irreversible and unbounded** (data is gone and the scope is the
          whole library) — `MediaCentaurWeb.Components.Modal` with
          `dismiss={:persistent}`, so a stray backdrop click or Escape cannot
          answer it. Today `clear_database` is the only action that qualifies.

      To extend `@exempt_files`, add the file with a one-line comment saying
      why that surface is genuinely outside the convention.

      Source: the audit-remediation campaign, Stage 8
      (`campaigns/audit-remediation-2026-08.md`).
      """
    ]

  # The console is deliberately outside the input system (backtick opens it;
  # it must not take the arrow keys on a log-reading surface), so the d-pad
  # argument that motivates this check does not reach it.
  @exempt_files [
    "components/console_components.ex",
    "credo/checks/native_confirm_dialog_test.exs"
  ]

  @data_confirm ~r/data-confirm\s*=/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        if Regex.match?(@data_confirm, line) do
          [issue_for(issue_meta, line_no)]
        else
          []
        end
      end)
    else
      []
    end
  end

  defp applies_to?(filename) do
    template_file?(filename) and not exempt?(filename)
  end

  defp template_file?(filename) do
    String.contains?(filename, "lib/media_centaur_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex"))
  end

  defp exempt?(filename) do
    Enum.any?(@exempt_files, &String.contains?(filename, &1))
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "`data-confirm` renders the native browser dialog, which is unthemed " <>
          "and not d-pad reachable. Drop the confirmation, arm the button in " <>
          "place, or use a persistent `<.modal>`. See " <>
          "MediaCentaur.Credo.Checks.NativeConfirmDialog.",
      trigger: "data-confirm=",
      line_no: line_no
    )
  end
end
