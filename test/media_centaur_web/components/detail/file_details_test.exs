defmodule MediaCentaurWeb.Components.Detail.MoreInfo.FileDetailsTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Detail.MoreInfo.FileDetails

  defp media_info(overrides) do
    Map.merge(
      %{
        container_title: nil,
        duration_seconds: 6073,
        video_codec: "HEVC",
        width: 3840,
        height: 2160,
        audio_summary: "TrueHD 7.1"
      },
      overrides
    )
  end

  describe "tech_line/1" do
    test "joins duration, codec, resolution, and audio with dots" do
      assert FileDetails.tech_line(media_info(%{})) == "1h 41m · HEVC · 3840×2160 · TrueHD 7.1"
    end

    test "durations under an hour omit the hour segment (UIDR-004)" do
      assert FileDetails.tech_line(media_info(%{duration_seconds: 2712})) =~ "45m ·"
      refute FileDetails.tech_line(media_info(%{duration_seconds: 2712})) =~ "0h"
    end

    test "missing facts drop out instead of leaving separators" do
      line =
        FileDetails.tech_line(
          media_info(%{video_codec: nil, width: nil, height: nil, audio_summary: nil})
        )

      assert line == "1h 41m"
    end

    test "nothing probed is the empty string" do
      empty =
        media_info(%{
          duration_seconds: nil,
          video_codec: nil,
          width: nil,
          height: nil,
          audio_summary: nil
        })

      assert FileDetails.tech_line(empty) == ""
    end
  end
end
