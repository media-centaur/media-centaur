defmodule MediaCentarr.SubtitlesTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Subtitles

  describe "aggregate_languages/1" do
    test "returns [] for an empty file list" do
      assert Subtitles.aggregate_languages([]) == []
    end

    test "returns [] when files have no subtitle_tracks" do
      files = [%{subtitle_tracks: []}, %{subtitle_tracks: []}]
      assert Subtitles.aggregate_languages(files) == []
    end

    test "extracts and dedupes ISO codes from a single file" do
      files = [
        %{
          subtitle_tracks: [
            %{"kind" => "embedded", "language" => "en", "source" => "stream:2"},
            %{"kind" => "embedded", "language" => "es", "source" => "stream:3"}
          ]
        }
      ]

      assert Subtitles.aggregate_languages(files) == ["en", "es"]
    end

    test "dedupes across multiple linked files" do
      files = [
        %{
          subtitle_tracks: [%{"kind" => "embedded", "language" => "en", "source" => "stream:2"}]
        },
        %{
          subtitle_tracks: [
            %{"kind" => "embedded", "language" => "en", "source" => "stream:2"},
            %{"kind" => "embedded", "language" => "fr", "source" => "stream:4"}
          ]
        }
      ]

      assert Subtitles.aggregate_languages(files) == ["en", "fr"]
    end

    test "sorts known languages alphabetically, with nil last (for unknown sidecars)" do
      files = [
        %{
          subtitle_tracks: [
            %{"kind" => "sidecar", "language" => nil, "source" => "/x/Movie.forced.srt"},
            %{"kind" => "embedded", "language" => "fr", "source" => "stream:5"},
            %{"kind" => "embedded", "language" => "de", "source" => "stream:3"},
            %{"kind" => "embedded", "language" => "en", "source" => "stream:2"}
          ]
        }
      ]

      assert Subtitles.aggregate_languages(files) == ["de", "en", "fr", nil]
    end

    test "collapses multiple unknown-language sidecars to a single nil" do
      files = [
        %{
          subtitle_tracks: [
            %{"kind" => "sidecar", "language" => nil, "source" => "/x/Movie.forced.srt"},
            %{"kind" => "sidecar", "language" => nil, "source" => "/x/Movie.sdh.srt"}
          ]
        }
      ]

      assert Subtitles.aggregate_languages(files) == [nil]
    end

    test "tolerates missing or nil subtitle_tracks fields" do
      files = [%{subtitle_tracks: nil}, %{}]
      assert Subtitles.aggregate_languages(files) == []
    end
  end
end
