defmodule MediaCentarr.Subtitles do
  use Boundary, deps: [], exports: [Track]

  @moduledoc """
  Public API for subtitle detection and aggregation.

  Two responsibilities:

    * `detect/1` runs every available detector against a video file
      path and returns a deduped list of `Track` values. Used at
      pipeline-import time and from the maintenance backfill.
    * `aggregate_languages/1` is the read-side helper for the UI.
      Given the linked-files for an entity (already preloaded), it
      returns a deduped, sorted list of language codes (with a single
      trailing `nil` if any unknown-language sidecar exists). The UI
      treats `nil` as "external".

  Detectors live under `MediaCentarr.Subtitles.Detector.*`. Each is a
  pluggable source (today: ffprobe + sidecar). Adding a new source is
  a single insertion below — every consumer keeps the public API.

  This context is its own boundary with no domain dependencies, so it
  can be invoked from anywhere safely.
  """

  alias MediaCentarr.Subtitles.Detector
  alias MediaCentarr.Subtitles.Track

  # Order matters only for debugging clarity — `detect/1` dedupes, so
  # the result is the union regardless.
  @detectors [Detector.Ffprobe, Detector.Sidecar]

  @spec detect(String.t()) :: [Track.t()]
  def detect(file_path) when is_binary(file_path) do
    @detectors
    |> Enum.flat_map(&run_detector(&1, file_path))
    |> Enum.uniq_by(&{&1.kind, &1.source})
  end

  @spec aggregate_languages([struct() | map()]) :: [String.t() | nil]
  def aggregate_languages(files) when is_list(files) do
    files
    |> Enum.flat_map(&extract_languages/1)
    |> sort_with_nil_last()
  end

  defp run_detector(Detector.Ffprobe, file_path), do: Detector.Ffprobe.probe(file_path)
  defp run_detector(Detector.Sidecar, file_path), do: Detector.Sidecar.scan(file_path)

  defp extract_languages(file) do
    file
    |> get_subtitle_tracks()
    |> Enum.map(&track_language/1)
  end

  defp get_subtitle_tracks(file) do
    case Map.get(file, :subtitle_tracks) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp track_language(%{"language" => lang}), do: lang
  defp track_language(%Track{language: lang}), do: lang
  defp track_language(_), do: nil

  defp sort_with_nil_last(languages) do
    {known, unknown} = Enum.split_with(languages, &is_binary/1)

    sorted_known = known |> Enum.uniq() |> Enum.sort()

    if unknown == [], do: sorted_known, else: sorted_known ++ [nil]
  end
end
