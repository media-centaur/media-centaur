defmodule MediaCentaur.Library.MediaProbeTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.MediaProbe

  defp fixture_json(overrides \\ %{}) do
    %{
      "streams" => [
        # Embedded cover art — ffprobe reports it as a video stream.
        %{
          "codec_type" => "video",
          "codec_name" => "mjpeg",
          "width" => 600,
          "height" => 882,
          "disposition" => %{"attached_pic" => 1}
        },
        %{
          "codec_type" => "video",
          "codec_name" => "hevc",
          "width" => 3840,
          "height" => 2160,
          "disposition" => %{"attached_pic" => 0}
        },
        %{
          "codec_type" => "audio",
          "codec_name" => "dts",
          "profile" => "DTS-HD MA",
          "channels" => 6,
          "channel_layout" => "5.1(side)"
        },
        %{"codec_type" => "audio", "codec_name" => "ac3", "channels" => 6, "channel_layout" => "5.1"},
        %{"codec_type" => "subtitle", "codec_name" => "hdmv_pgs_subtitle"}
      ],
      "format" => %{
        "duration" => "6073.611000",
        "tags" => %{"TITLE" => "Sample.Movie.1997.2160p.BluRay-GRP"}
      }
    }
    |> Map.merge(overrides)
    |> Jason.encode!()
  end

  describe "parse/1" do
    test "extracts title tag, duration, feature video, and the audio summary" do
      assert {:ok, attrs} = MediaProbe.parse(fixture_json())

      assert attrs.container_title == "Sample.Movie.1997.2160p.BluRay-GRP"
      assert attrs.duration_seconds == 6074
      assert attrs.video_codec == "HEVC"
      assert attrs.width == 3840
      assert attrs.height == 2160
      assert attrs.audio_summary == "DTS-HD MA 5.1 · AC3 5.1"
    end

    test "the feature video stream skips embedded cover art (attached_pic)" do
      assert {:ok, attrs} = MediaProbe.parse(fixture_json())
      refute attrs.video_codec == "MJPEG"
      assert attrs.width == 3840
    end

    test "title tag keys match case-insensitively — muxers write both 'title' and 'TITLE'" do
      json =
        fixture_json(%{"format" => %{"duration" => "10.0", "tags" => %{"title" => "lowercase"}}})

      assert {:ok, %{container_title: "lowercase"}} = MediaProbe.parse(json)
    end

    test "no tags → nil container_title; everything else still parses" do
      json = fixture_json(%{"format" => %{"duration" => "100.5"}})

      assert {:ok, attrs} = MediaProbe.parse(json)
      assert attrs.container_title == nil
      assert attrs.duration_seconds == 101
      assert attrs.video_codec == "HEVC"
    end

    test "identical audio tracks collapse to a count" do
      json =
        fixture_json(%{
          "streams" => [
            %{
              "codec_type" => "audio",
              "codec_name" => "dts",
              "channels" => 2,
              "channel_layout" => "stereo"
            },
            %{
              "codec_type" => "audio",
              "codec_name" => "dts",
              "channels" => 2,
              "channel_layout" => "stereo"
            }
          ]
        })

      assert {:ok, %{audio_summary: "DTS stereo ×2", video_codec: nil}} = MediaProbe.parse(json)
    end

    test "channel count is the fallback when no layout is reported" do
      json =
        fixture_json(%{
          "streams" => [%{"codec_type" => "audio", "codec_name" => "eac3", "channels" => 6}]
        })

      assert {:ok, %{audio_summary: "DDP 6ch"}} = MediaProbe.parse(json)
    end

    test "unparseable output is :error" do
      assert MediaProbe.parse("not json") == :error
      assert MediaProbe.parse("[1,2,3]") == :error
    end
  end

  describe "probe/1 (runner seam)" do
    test "the test-env runner is Disabled — every probe fails cleanly with no subprocess" do
      assert MediaProbe.probe("/nonexistent/file.mkv") == :error
    end
  end
end
