defmodule MediaCentaur.Library.MediaProbe do
  @moduledoc """
  Reads display-oriented technical metadata out of a media container via
  `ffprobe`: the embedded container **title tag**, the measured
  **duration**, the **video codec + resolution**, and a one-line
  **audio-track summary**.

  Display-only by design — the values feed `Library.FileMediaInfo` and
  the More-info pane. Nothing gates or judges on them; the payoff is
  legibility: a container whose author titled it as a different movie
  than its filename claims (a renamed fake release) is visible at a
  glance.

  Soft-depends on `ffprobe` (same policy as the subtitles detector): a
  missing binary, an unreadable file, or unparseable output returns
  `:error` cleanly and no metadata is stored.

  Subprocess invocation goes through the `:media_probe_runner`
  application env — `SystemRunner` in dev/prod, `Disabled` under test
  (ADR-016: tests never touch the real filesystem or spawn probes).
  `parse/1` is pure and carries the tests.
  """

  alias MediaCentaur.Config

  @default_executable "ffprobe"

  @args ~w(-v error -show_entries
           format=duration:format_tags=title:stream=codec_type,codec_name,profile,width,height,channels,channel_layout:stream_disposition=attached_pic
           -of json)

  @type attrs :: %{
          container_title: String.t() | nil,
          duration_seconds: non_neg_integer() | nil,
          video_codec: String.t() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          audio_summary: String.t() | nil
        }

  @spec probe(String.t()) :: {:ok, attrs()} | :error
  def probe(file_path) when is_binary(file_path) do
    case runner().run(executable(), @args ++ [file_path]) do
      {stdout, 0} -> parse(stdout)
      _ -> :error
    end
  end

  @doc "Pure parse of ffprobe's JSON output into `t:attrs/0`."
  @spec parse(binary()) :: {:ok, attrs()} | :error
  def parse(stdout) when is_binary(stdout) do
    case Jason.decode(stdout) do
      {:ok, %{} = probed} ->
        streams = Map.get(probed, "streams", [])
        video = main_video_stream(streams)

        {:ok,
         %{
           container_title: container_title(probed),
           duration_seconds: duration_seconds(probed),
           video_codec: video && video_codec_label(video["codec_name"]),
           width: video && video["width"],
           height: video && video["height"],
           audio_summary: audio_summary(streams)
         }}

      _ ->
        :error
    end
  end

  defp runner do
    Application.get_env(:media_centaur, :media_probe_runner, __MODULE__.SystemRunner)
  end

  defp executable, do: Config.get(:ffprobe_path) || @default_executable

  # Tag keys keep whatever case the muxer wrote ("title" vs "TITLE").
  defp container_title(%{"format" => %{"tags" => tags}}) when is_map(tags) do
    Enum.find_value(tags, fn {key, value} ->
      if String.downcase(key) == "title" and is_binary(value) and value != "", do: value
    end)
  end

  defp container_title(_probed), do: nil

  defp duration_seconds(%{"format" => %{"duration" => duration}}) when is_binary(duration) do
    case Float.parse(duration) do
      {seconds, _rest} -> round(seconds)
      :error -> nil
    end
  end

  defp duration_seconds(_probed), do: nil

  # The real feature video — not embedded cover art, which ffprobe also
  # reports as a video stream (mjpeg/png with the attached_pic flag).
  defp main_video_stream(streams) do
    Enum.find(streams, fn stream ->
      stream["codec_type"] == "video" and
        get_in(stream, ["disposition", "attached_pic"]) != 1
    end)
  end

  defp video_codec_label("hevc"), do: "HEVC"
  defp video_codec_label("h264"), do: "H.264"
  defp video_codec_label("av1"), do: "AV1"
  defp video_codec_label("vp9"), do: "VP9"
  defp video_codec_label(other) when is_binary(other), do: String.upcase(other)
  defp video_codec_label(_), do: nil

  defp audio_summary(streams) do
    labels =
      streams
      |> Enum.filter(&(&1["codec_type"] == "audio"))
      |> Enum.map(&audio_label/1)
      |> Enum.reject(&is_nil/1)

    case labels do
      [] ->
        nil

      labels ->
        # Keep stream order (the main track leads); collapse repeats.
        counts = Enum.frequencies(labels)

        labels
        |> Enum.uniq()
        |> Enum.map_join(" · ", fn label ->
          case counts[label] do
            1 -> label
            count -> "#{label} ×#{count}"
          end
        end)
    end
  end

  defp audio_label(stream) do
    case audio_codec_label(stream["codec_name"], stream["profile"]) do
      nil -> nil
      codec -> String.trim("#{codec} #{channel_label(stream)}")
    end
  end

  defp audio_codec_label("truehd", _profile), do: "TrueHD"
  defp audio_codec_label("eac3", _profile), do: "DDP"
  defp audio_codec_label("ac3", _profile), do: "AC3"
  defp audio_codec_label("dts", "DTS-HD MA"), do: "DTS-HD MA"
  defp audio_codec_label("dts", _profile), do: "DTS"
  defp audio_codec_label("aac", _profile), do: "AAC"
  defp audio_codec_label("flac", _profile), do: "FLAC"
  defp audio_codec_label("opus", _profile), do: "Opus"
  defp audio_codec_label(other, _profile) when is_binary(other), do: String.upcase(other)
  defp audio_codec_label(_other, _profile), do: nil

  # "5.1(side)" → "5.1"; no layout → "6ch"; nothing known → "".
  defp channel_label(%{"channel_layout" => layout}) when is_binary(layout) and layout != "" do
    layout |> String.replace(~r/\(.*\)/, "") |> String.trim()
  end

  defp channel_label(%{"channels" => channels}) when is_integer(channels), do: "#{channels}ch"
  defp channel_label(_stream), do: ""

  defmodule SystemRunner do
    @moduledoc "Production runner — shells out to `ffprobe`."

    @spec run(String.t(), [String.t()]) :: {binary(), non_neg_integer()} | {:error, term()}
    def run(executable, args) do
      System.cmd(executable, args, stderr_to_stdout: true)
    rescue
      error in [ErlangError] -> {:error, error}
    end
  end

  defmodule Disabled do
    @moduledoc "Test runner — probing is off (ADR-016), every probe fails cleanly."

    @spec run(String.t(), [String.t()]) :: {binary(), pos_integer()}
    def run(_executable, _args), do: {"", 1}
  end
end
