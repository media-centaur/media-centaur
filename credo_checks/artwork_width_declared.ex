defmodule MediaCentaur.Credo.Checks.ArtworkWidthDeclared do
  use Credo.Check,
    id: "MC0028",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every `<img>` under `lib/media_centaur_web/` that points at local
      artwork must declare the width it paints at, by passing the URL
      through `MediaCentaurWeb.LiveHelpers.sized_image_url/2`.

      Local artwork masters are big on purpose — backdrops are stored at
      up to 3840×2160 so the home hero renders sharply on a 4K panel.
      Omitting a width serves that master to whatever box asked, and
      because every image is `decoding="sync"` (UIDR-012), the decode
      blocks paint. A 40px poster thumbnail decoding a 1120px master is
      pure latency, and the home page was fetching ~11 MB of masters this
      way to paint a handful of cards.

      The failure is invisible in review: a full-bleed hero that wants the
      master and a thumbnail that forgot its width look identical. So the
      width vocabulary is closed and always stated.

          # preferred — a device-pixel width
          <img src={sized_image_url(@item.backdrop_url, 1280)} />

          # preferred — this surface really does span the viewport
          <img src={sized_image_url(@hero.backdrop_url, :full_bleed)} />

          # preferred — the surface owns its builder so ArtworkWarmup can
          # prefetch the identical URL (see LiveHelpers.poster_src/1)
          <img src={poster_src(@entry.poster_url)} />

          # flagged — serves the full-resolution master by omission
          <img src={@item.backdrop_url} />

      Size the width to the rendered box × the target device-pixel-ratio
      (≈2× — the app composes at 1920 CSS px and runs on 4K panels), then
      let `ImageServer` snap up to its width ladder. Over-asking is cheap:
      `ImageFiles.derivative/2` never upscales.

      Remote TMDB URLs are ignored — they already name their size in the
      path (`/t/p/w92/...`) and ImageServer can't resize them.

      This check cannot tell you whether a new surface should also be
      warmed by `MediaCentaurWeb.ArtworkWarmup` — "first screen" is a
      judgment call. See that module's "Adding a surface" section.
      """
    ]

  # Assign/field names that carry a local `/media-images/...` URL, plus the
  # helper that builds one from a stored path. This is the artwork role
  # vocabulary (`Library.Image` roles); a `src` mentioning one of these is
  # pointing at something ImageServer serves and can resize.
  @artwork_source ~r/\b(backdrop_url|logo_url|poster_url|thumb_url|art_url|Image\.web_path)\b/

  # The declaration itself. `sized_image_url/2` is the direct form;
  # `*_src(...)` is a surface's own builder, which declares the width inside
  # the function where this check still sees it.
  @width_declared ~r/\b(sized_image_url|\w+_src)\s*\(/

  # ImageServer can't resize a remote host, and TMDB URLs name their size in
  # the path already.
  @remote_url ~r|image\.tmdb\.org|

  @src_attribute ~r/\bsrc=\{/

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if template_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        if undeclared_artwork_src?(line) do
          [issue_for(issue_meta, line_no)]
        else
          []
        end
      end)
    else
      []
    end
  end

  defp undeclared_artwork_src?(line) do
    Regex.match?(@src_attribute, line) and
      Regex.match?(@artwork_source, line) and
      not Regex.match?(@remote_url, line) and
      not Regex.match?(@width_declared, line)
  end

  defp template_file?(filename) do
    String.contains?(filename, "lib/media_centaur_web/") and
      (String.ends_with?(filename, ".ex") or String.ends_with?(filename, ".heex"))
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Local artwork must declare the width it paints at: wrap this `src` in " <>
          "`sized_image_url(url, <device_px>)`, or `sized_image_url(url, :full_bleed)` " <>
          "if the surface genuinely spans the viewport. Omitting it serves the " <>
          "full-resolution master and blocks paint on its decode (UIDR-012).",
      trigger: "src={",
      line_no: line_no
    )
  end
end
