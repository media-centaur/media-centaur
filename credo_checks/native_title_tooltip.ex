defmodule MediaCentaur.Credo.Checks.NativeTitleTooltip do
  use Credo.Check,
    id: "MC0042",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Templates under `lib/media_centaur_web/` must not use the native
      `title` attribute, nor an SVG `<title>` element, for a hover label.
      The browser draws that tooltip outside the page in its own chrome:
      it ignores the theme and the UI scale, Chromium clips its box, and
      keyboard or gamepad focus never reveals it.

      The app has one tooltip — the `.app-tooltip` element in the layout,
      driven by the `Tooltip` hook (`assets/js/hooks/tooltip.js`). Put the
      label in `data-tip` instead; the hook shows it on hover and on
      keyboard/gamepad focus, themed, scaled and kept on screen.

          # preferred
          <span class="truncate-left" data-tip={path}><bdo dir="ltr">{path}</bdo></span>
          <.button variant="dismiss" shape="square" data-tip="Close" aria-label="Close">
            <.icon name="hero-x-mark-mini" />
          </.button>

          # NOT preferred
          <span class="truncate-left" title={path}>…</span>
          <.button variant="dismiss" title="Close">…</.button>
          <rect …><title>{label}</title></rect>

      `data-tip` is a hover label only. An icon-only control still needs
      `aria-label` for its accessible name — `title` used to double as
      both, `data-tip` does not.

      Only HTML elements and the two components that forward global
      attributes to one (`<.button>`, `<.link>`) are checked. A component
      attribute named `title` (`<.page_header title=…>`,
      `<:item title=…>`) is data, not a tooltip, and is left alone.
      """
    ]

  # Components whose `title` lands on a native element via `@rest`.
  @forwarding_components ~w(.button .link .armed_button)

  # A `title=` attribute, as opposed to `phx-value-title=`, `data-title=`
  # or `?title=` in a URL.
  @title_attr ~r/(?<=\s)title=/

  # An SVG/HTML `<title>` element. `<.live_title>` does not match.
  @title_element ~r/<title[\s>]/

  # A `~H` sigil's body; a `.heex` file is one region.
  @sigil_h ~r/~H"""(.*?)"""/s

  # The start of a tag: an HTML element or a function component.
  @tag_open ~r/<(\.?[A-Za-z][\w.:-]*)/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      source = SourceFile.source(source_file)

      source
      |> template_regions(filename)
      |> Enum.flat_map(fn {offset, template} ->
        line = fn pos -> line_of(source, offset + pos) end
        attribute_issues(template, issue_meta, line) ++ element_issues(template, issue_meta, line)
      end)
    else
      []
    end
  end

  defp applies_to?(filename) do
    String.contains?(filename, "lib/media_centaur_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex")) and
      not String.ends_with?(filename, "native_title_tooltip_test.exs")
  end

  # Prose in a moduledoc may say `<title>` or `title=`; only markup counts.
  defp template_regions(source, filename) do
    if String.ends_with?(filename, ".heex") do
      [{0, source}]
    else
      @sigil_h
      |> Regex.scan(source, return: :index)
      |> Enum.map(fn [_, {pos, len}] -> {pos, binary_part(source, pos, len)} end)
    end
  end

  defp attribute_issues(template, issue_meta, line) do
    tags = Regex.scan(@tag_open, template, return: :index)

    @title_attr
    |> Regex.scan(template, return: :index)
    |> Enum.flat_map(fn [{pos, _len}] ->
      case enclosing_tag(tags, template, pos) do
        {:ok, name} ->
          if tooltip_bearing?(name),
            do: [issue_for(issue_meta, line.(pos), "title=")],
            else: []

        :none ->
          []
      end
    end)
  end

  defp element_issues(template, issue_meta, line) do
    @title_element
    |> Regex.scan(template, return: :index)
    |> Enum.map(fn [{pos, _len}] -> issue_for(issue_meta, line.(pos), "<title>") end)
  end

  # The nearest tag opened before `pos` whose attribute list is still open
  # at `pos`: no `>` at brace depth zero between the two, and `pos` itself
  # outside any `{…}` expression.
  defp enclosing_tag(tags, source, pos) do
    tags
    |> Enum.filter(fn [{start, _}, _] -> start < pos end)
    |> List.last()
    |> case do
      nil ->
        :none

      [{start, len}, {name_start, name_len}] ->
        between = binary_part(source, start + len, pos - start - len)

        if still_in_tag?(between),
          do: {:ok, binary_part(source, name_start, name_len)},
          else: :none
    end
  end

  defp still_in_tag?(between) do
    between
    |> String.graphemes()
    |> Enum.reduce_while(0, fn
      "{", depth -> {:cont, depth + 1}
      "}", depth -> {:cont, max(depth - 1, 0)}
      ">", 0 -> {:halt, :closed}
      _, depth -> {:cont, depth}
    end)
    |> Kernel.==(0)
  end

  defp tooltip_bearing?(name) do
    html_element?(name) or name in @forwarding_components
  end

  defp html_element?(<<first::utf8, _::binary>> = name) do
    first in ?a..?z and not String.contains?(name, ".")
  end

  defp line_of(source, pos) do
    source
    |> binary_part(0, pos)
    |> String.graphemes()
    |> Enum.count(&(&1 == "\n"))
    |> Kernel.+(1)
  end

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Native `#{trigger}` draws the browser's own tooltip — unthemed, unscaled, clipped. " <>
          "Put the label in `data-tip` (the app tooltip, hooks/tooltip.js); an icon-only " <>
          "control also keeps `aria-label`. See MediaCentaur.Credo.Checks.NativeTitleTooltip.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
