defmodule MediaCentaur.Credo.Checks.ImgAttributeDefaults do
  use Credo.Check,
    id: "MC0016",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Templates under `lib/media_centaur_web/` must not use
      `loading="lazy"` on `<img>` tags except inside the explicit
      allowlist below. Media Centaur is a specialized desktop app
      with a bounded library; lazy-loading defers the fetch until
      intersection-observer fires, which is exactly the perceived
      latency we're paying to remove (ADR-012).

      Use `loading="eager"` with `decoding="sync"` instead. For
      hero / page-dominant images, also set `fetchpriority="high"`.

          # preferred — instant paint
          <img
            src={...}
            loading="eager"
            decoding="sync"
          />

          # preferred — hero
          <img
            src={...}
            loading="eager"
            decoding="sync"
            fetchpriority="high"
          />

      Lazy is allowed only where the rendered set can grow into
      the dozens behind a reveal:

      * `cast_grid.ex` — cast headshots inside the "More Info"
        pane (often 50+; user must reveal to see them)
      * `track_modal.ex` — track-search result thumbnails
        (unbounded N inside a deliberately opened modal)

      To extend the allowlist, add the file to `@exempt_files` with
      a one-line comment explaining why this surface is genuinely
      reveal-bounded rather than in the page flow.

      Source: ADR-012 (`decisions/user-interface/2026-05-20-012-desktop-app-rendering-defaults.md`).
      """
    ]

  # Surfaces that legitimately need lazy because the rendered set
  # can grow into the dozens behind an explicit reveal.
  @exempt_files [
    "components/detail/more_info/cast_grid.ex",
    "components/track_modal.ex",
    "credo/checks/img_attribute_defaults_test.exs"
  ]

  @lazy_loading_attr ~r/loading\s*=\s*"lazy"/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if applies_to?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        if Regex.match?(@lazy_loading_attr, line) do
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
    Enum.any?(@exempt_files, &String.ends_with?(filename, &1))
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        ~s(Replace `loading="lazy"` with `loading="eager" decoding="sync"` ) <>
          "(this is a desktop app — see ADR-012). If this surface is genuinely " <>
          "reveal-bounded, add the file to `@exempt_files` in " <>
          "`MediaCentaur.Credo.Checks.ImgAttributeDefaults` with a justification.",
      trigger: ~s(loading="lazy"),
      line_no: line_no
    )
  end
end
