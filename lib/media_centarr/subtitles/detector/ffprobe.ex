defmodule MediaCentarr.Subtitles.Detector.Ffprobe do
  @moduledoc """
  Reads embedded subtitle tracks from a video container via `ffprobe`.

  Soft-depends on the `ffprobe` binary. If `ffprobe` is missing or any
  call fails, `probe/1` returns `[]` cleanly — the feature degrades to
  sidecar-only detection without crashing the import pipeline.

  Subprocess invocation goes through `Detector.Runner`, which is the
  injectable seam for tests. Production calls flow to
  `System.cmd("ffprobe", ...)`; tests configure
  `:media_centarr, :subtitles_runner` to return canned output.
  """

  alias MediaCentarr.Config
  alias MediaCentarr.Subtitles.Detector.Runner
  alias MediaCentarr.Subtitles.LanguageCode
  alias MediaCentarr.Subtitles.Track

  @default_executable "ffprobe"

  # `-v error` mutes the friendly chatter; `-select_streams s` filters
  # to subtitle streams only; `-show_entries` keeps the JSON small;
  # `-of json` gives us a parseable result.
  @args ~w(-v error -select_streams s -show_entries stream=index:stream_tags=language -of json)

  @spec probe(String.t()) :: [Track.t()]
  def probe(file_path) when is_binary(file_path) do
    case Runner.run(executable(), @args ++ [file_path]) do
      {stdout, 0} -> parse(stdout)
      _ -> []
    end
  end

  defp executable, do: Config.get(:ffprobe_path) || @default_executable

  defp parse(stdout) do
    case Jason.decode(stdout) do
      {:ok, %{"streams" => streams}} when is_list(streams) -> Enum.map(streams, &to_track/1)
      _ -> []
    end
  end

  defp to_track(%{"index" => index} = stream) do
    raw_language = get_in(stream, ["tags", "language"])

    %Track{
      kind: :embedded,
      language: LanguageCode.normalize(raw_language),
      source: "stream:#{index}"
    }
  end
end
