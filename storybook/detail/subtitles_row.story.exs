defmodule MediaCentarrWeb.Storybook.Detail.SubtitlesRow do
  @moduledoc """
  Compact label-plus-codes row showing the subtitle languages available
  on a movie's linked file(s). Codes are pre-aggregated by
  `MediaCentarr.Subtitles.aggregate_languages/1`; the component is pure
  display.

  `nil` entries render as the literal text `external` — those came from
  sidecar files whose filename suffix didn't match a known ISO code.
  Empty list renders nothing (no row in the DOM at all), so the panel
  stays clean for movies without detected subs.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.SubtitlesRow.subtitles_row/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full max-w-3xl p-4">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :none,
        description: "Empty list — the row is omitted entirely. Verify nothing renders.",
        attributes: %{languages: []}
      },
      %Variation{
        id: :single,
        description: "One language — most curated rips have at least an English track.",
        attributes: %{languages: ["en"]}
      },
      %Variation{
        id: :multi,
        description: "Several known languages, alphabetical.",
        attributes: %{languages: ["en", "es", "fr"]}
      },
      %Variation{
        id: :only_external,
        description:
          "Only an unknown-language sidecar (e.g. `Movie.forced.srt`) — surfaces as `external`.",
        attributes: %{languages: [nil]}
      },
      %Variation{
        id: :mixed_with_external,
        description: "Known languages plus an external — `external` always sorts last.",
        attributes: %{languages: ["en", nil]}
      },
      %Variation{
        id: :many,
        description: "A wide multi-language rip — confirms the layout doesn't wrap awkwardly.",
        attributes: %{languages: ["de", "en", "es", "fr", "it", "ja", "pt"]}
      }
    ]
  end
end
