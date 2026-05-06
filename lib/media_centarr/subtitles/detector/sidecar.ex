defmodule MediaCentarr.Subtitles.Detector.Sidecar do
  @moduledoc """
  Finds subtitle sidecar files sitting next to a video file.

  A sidecar is a file in the same directory whose basename (the part
  before extensions) matches the video's basename, and whose extension
  is one of the recognised subtitle formats. Examples:

      Sample.Movie.2020.mkv
      Sample.Movie.2020.srt          # bare-extension; language: nil
      Sample.Movie.2020.en.srt       # 2-letter ISO; language: "en"
      Sample.Movie.2020.spa.srt      # 3-letter ISO; language: "es"
      Sample.Movie.2020.forced.srt   # not an ISO code; language: nil

  Sidecars don't carry self-describing language metadata — the only
  signal is the filename suffix between the basename and the extension.
  Anything that doesn't normalise through `LanguageCode.normalize/1`
  yields `language: nil`, which the UI surfaces as "external".

  Pure given a path: this module's only side effect is `File.ls/1`.
  """

  alias MediaCentarr.Subtitles.LanguageCode
  alias MediaCentarr.Subtitles.Track

  @subtitle_extensions ~w(.srt .vtt .ass .ssa .sub)

  @spec scan(String.t()) :: [Track.t()]
  def scan(video_path) when is_binary(video_path) do
    dir = Path.dirname(video_path)
    video_basename = strip_extension(Path.basename(video_path))

    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, &match_sidecar(&1, video_basename, dir))

      {:error, _} ->
        []
    end
  end

  defp match_sidecar(entry, video_basename, dir) do
    ext = String.downcase(Path.extname(entry))

    if ext in @subtitle_extensions do
      remainder = String.slice(entry, 0, byte_size(entry) - byte_size(ext))
      build_track(remainder, video_basename, Path.join(dir, entry))
    else
      []
    end
  end

  defp build_track(remainder, video_basename, full_path) do
    cond do
      iequal?(remainder, video_basename) ->
        [%Track{kind: :sidecar, language: nil, source: full_path}]

      String.length(remainder) > String.length(video_basename) + 1 ->
        # Try to peel a language suffix: <basename>.<lang>
        prefix_len = String.length(video_basename)

        prefix = String.slice(remainder, 0, prefix_len)

        with true <- iequal?(prefix, video_basename),
             "." <> rest <- String.slice(remainder, prefix_len, String.length(remainder)) do
          language = LanguageCode.normalize(rest)
          [%Track{kind: :sidecar, language: language, source: full_path}]
        else
          _ -> []
        end

      true ->
        []
    end
  end

  defp strip_extension(name) do
    ext = Path.extname(name)
    String.slice(name, 0, byte_size(name) - byte_size(ext))
  end

  defp iequal?(a, b), do: String.downcase(a) == String.downcase(b)
end
