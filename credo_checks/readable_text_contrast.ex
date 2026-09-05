defmodule MediaCentaur.Credo.Checks.ReadableTextContrast do
  use Credo.Check,
    id: "MC0034",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Readable text under `lib/media_centaur_web/` keeps a contrast floor:
      `text-base-content/55` or above. Composited on the dark theme's
      `base-100`, `/40` is 3.2:1 and `/50` is 4.2:1 — both under the 4.5:1
      that small text needs — while `/55` clears it at 4.75:1.

          # preferred
          <p class="text-sm text-base-content/60">Last scanned 2 minutes ago</p>
          <h3 class="text-xs uppercase tracking-wider text-base-content/55">Library</h3>

          # NOT preferred
          <p class="text-sm text-base-content/40">Last scanned 2 minutes ago</p>

      Opacities of `/50` and below stay available for what is not read as
      text: icons, spinners, separator glyphs, placeholders and disabled
      controls. The check recognises those by a marker on the same line —
      an icon (`hero-*`, `size-*`), a `loading` spinner, a
      `placeholder:`/`disabled:` variant, a `select-none` separator, or a
      bare `·`/`&middot;` glyph. A class string that only ever tints an
      icon should carry its `size-*` so the line says so.

      Variant-prefixed classes (`hover:text-base-content/40`) are not
      flagged — the resting state is what the check holds.

      Source: audit DS25; the `user-interface` skill's text hierarchy.
      """
    ]

  @floor 55

  # `text-base-content/<n>` not preceded by a variant prefix (`hover:`) or
  # another token character.
  @opacity_class ~r{(?<![:\w-])text-base-content/(\d+)\b}

  # Same-line markers for text that is not read as text.
  @decorative ~r/hero-|size-|\bloading\b|placeholder:|disabled:|select-none|·|&middot;/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        case low_contrast_class(line) do
          nil -> []
          trigger -> [issue_for(issue_meta, line_no, trigger)]
        end
      end)
    else
      []
    end
  end

  defp applies_to?(filename) do
    String.contains?(filename, "lib/media_centaur_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex")) and
      not String.ends_with?(filename, "readable_text_contrast_test.exs")
  end

  @doc false
  def low_contrast_class(line) do
    if Regex.match?(@decorative, line) do
      nil
    else
      @opacity_class
      |> Regex.scan(line)
      |> Enum.find_value(fn [whole, opacity] ->
        if String.to_integer(opacity) < @floor, do: whole
      end)
    end
  end

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Readable text stays at `text-base-content/#{@floor}` or above; `#{trigger}` fails " <>
          "the contrast floor. Below the floor is for icons, separators, placeholders and " <>
          "disabled controls (MC0034).",
      trigger: trigger,
      line_no: line_no
    )
  end
end
