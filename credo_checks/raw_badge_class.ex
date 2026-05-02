defmodule MediaCentarr.Credo.Checks.RawBadgeClass do
  use Credo.Check,
    id: "MC0008",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Templates under `lib/media_centarr_web/` must not use raw daisyUI
      `badge` classes directly. Go through the `<.badge>` component, which
      encodes the UIDR-002 badge variants (metric, type, info, success,
      warning, error, ghost) and sizes (xs, sm, md).

          # preferred
          <.badge>{@count}</.badge>
          <.badge variant="type">Movie</.badge>
          <.badge variant="success">Completed</.badge>

          # NOT preferred
          <span class="badge badge-sm">{@count}</span>
          <span class="badge badge-outline badge-sm">Movie</span>
          <span class={["badge badge-sm", state_class(@state)]}>...</span>

      For *status reasons* (review reasons, free-text entity states), UIDR-002
      requires plain colored text — `<span class="text-error">…</span>` —
      **not** a badge. The `<.badge>` component covers metric/type/state-chip
      cases only.

      Extra utility classes are still fine — pass them via the `class`
      attribute on `<.badge>`. Custom CSS classes that happen to end in
      `-badge` (e.g. `console-component-badge`) are not flagged; only the
      standalone daisyUI `badge` token triggers this check.

      The badge component itself (`core_components.ex`) is exempt — it
      owns the literal `badge` string. The acquisition logic helper
      `state_badge_class/1` is also exempt for now (returns class strings
      for legacy callers awaiting migration).

      Source: CLAUDE.md / UIDR-002.
      """
    ]

  # Any `class=` attribute (literal `class="..."` or expression `class={...}`).
  @class_attr_present ~r/class\s*=/

  # Any double-quoted string contents on the line.
  @any_quoted_string ~r/"([^"]*)"/

  # Standalone `badge` token (whitespace-delimited or value-edge).
  @badge_token ~r/(?:^|\s)badge(?:\s|$)/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        if raw_badge_class?(line) do
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
    String.contains?(filename, "lib/media_centarr_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex"))
  end

  # `core_components.ex` defines the `<.badge>` component itself — the only
  # place allowed to write the literal `badge` class string. The check's own
  # test file contains heredoc fixtures that intentionally include the
  # flagged pattern; skip it.
  defp exempt?(filename) do
    String.ends_with?(filename, "core_components.ex") or
      String.ends_with?(filename, "raw_badge_class_test.exs")
  end

  # A line is a violation if it both:
  #   (a) contains a `class=` attribute (literal or expression form), and
  #   (b) contains any quoted string with the standalone `badge` token.
  #
  # This catches both:
  #     class="badge ..."
  #     class={["badge ...", helper(...)]}
  #
  # Helper functions returning raw class strings (e.g. `state_badge_class/1`)
  # do not appear with a `class=` attribute on the same line and so are not
  # flagged here — those callers must be migrated to use the `<.badge>`
  # component with a typed variant instead.
  defp raw_badge_class?(line) do
    Regex.match?(@class_attr_present, line) and
      @any_quoted_string
      |> Regex.scan(line, capture: :all_but_first)
      |> List.flatten()
      |> Enum.any?(&Regex.match?(@badge_token, &1))
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Use the `<.badge>` component (with `variant` and `size`) instead of raw `badge` classes. " <>
          "See UIDR-002 / `MediaCentarrWeb.CoreComponents.badge/1`.",
      trigger: "badge",
      line_no: line_no
    )
  end
end
