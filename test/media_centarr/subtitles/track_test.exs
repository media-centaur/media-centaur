defmodule MediaCentarr.Subtitles.TrackTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Subtitles.Track

  describe "to_map/1 + from_map/1" do
    test "round-trips an embedded track" do
      track = %Track{kind: :embedded, language: "en", source: "stream:2"}
      assert track |> Track.to_map() |> Track.from_map() == track
    end

    test "round-trips a sidecar track with no language" do
      track = %Track{kind: :sidecar, language: nil, source: "/x/Sample.srt"}
      assert track |> Track.to_map() |> Track.from_map() == track
    end

    test "to_map/1 produces string-keyed JSON-friendly maps" do
      track = %Track{kind: :embedded, language: "fr", source: "stream:0"}
      assert Track.to_map(track) == %{"kind" => "embedded", "language" => "fr", "source" => "stream:0"}
    end

    test "from_map/1 returns nil for malformed input" do
      assert Track.from_map(%{}) == nil
      assert Track.from_map(%{"kind" => "embedded"}) == nil
      assert Track.from_map("not a map") == nil
    end
  end
end
