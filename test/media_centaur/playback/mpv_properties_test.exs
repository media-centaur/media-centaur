defmodule MediaCentaur.Playback.MpvPropertiesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.MpvProperties
  alias MediaCentaur.Playback.TrackResolver.Track

  describe "apply/3 — one property-change folded in" do
    test "keeps each observed value under its own name" do
      mirror =
        %MpvProperties{}
        |> MpvProperties.apply("time-pos", 12.5)
        |> MpvProperties.apply("duration", 1800.0)
        |> MpvProperties.apply("pause", true)
        |> MpvProperties.apply("chapter-list", [%{"title" => "Intro", "time" => 0.0}])
        |> MpvProperties.apply("chapter", 0)
        |> MpvProperties.apply("aid", 1)
        |> MpvProperties.apply("sid", false)
        |> MpvProperties.apply("playlist-count", 2)
        |> MpvProperties.apply("playlist-pos", 1)
        |> MpvProperties.apply("sub-text", "A line")

      assert %MpvProperties{
               position: 12.5,
               duration: 1800.0,
               paused: true,
               chapters: [%{"title" => "Intro", "time" => 0.0}],
               chapter: 0,
               aid: 1,
               sid: false,
               playlist_count: 2,
               playlist_pos: 1,
               subtitle_text: "A line"
             } = mirror
    end

    test "parses track-list into Track structs" do
      mirror =
        MpvProperties.apply(%MpvProperties{}, "track-list", [
          %{"id" => 1, "type" => "audio", "lang" => "eng"},
          %{"id" => 2, "type" => "sub", "lang" => "eng", "codec" => "hdmv_pgs_subtitle"}
        ])

      assert [%Track{index: 1, lang: "eng"}] = mirror.audio_tracks
      assert [%Track{index: 2, codec: "hdmv_pgs_subtitle"}] = mirror.subtitle_tracks
    end

    test "a value in an unexpected shape leaves the mirror as it was" do
      mirror = %MpvProperties{position: 10.0, duration: 100.0, chapters: [%{}], playlist_count: 2}

      assert MpvProperties.apply(mirror, "time-pos", nil) == mirror
      assert MpvProperties.apply(mirror, "duration", "soon") == mirror
      assert MpvProperties.apply(mirror, "pause", nil) == mirror
      assert MpvProperties.apply(mirror, "chapter-list", nil) == mirror
      assert MpvProperties.apply(mirror, "track-list", nil) == mirror
      assert MpvProperties.apply(mirror, "playlist-count", nil) == mirror
      assert MpvProperties.apply(mirror, "unobserved", 1) == mirror
    end

    test "a chapter that is not an index, and an empty or absent subtitle line, read nil" do
      mirror = %MpvProperties{chapter: 2, subtitle_text: "A line"}

      assert MpvProperties.apply(mirror, "chapter", nil).chapter == nil
      assert MpvProperties.apply(mirror, "sub-text", "").subtitle_text == nil
      assert MpvProperties.apply(mirror, "sub-text", nil).subtitle_text == nil
    end
  end

  describe "reset_for_file/1 — the next file of a playlist" do
    test "clears what the file owns and keeps the selected tracks and the playlist shape" do
      mirror = %MpvProperties{
        position: 1200.0,
        duration: 2600.0,
        chapters: [%{"title" => "Intro", "time" => 0.0}],
        chapter: 1,
        audio_tracks: [%Track{index: 1}],
        subtitle_tracks: [%Track{index: 2}],
        aid: 1,
        sid: 2,
        playlist_count: 3,
        playlist_pos: 1,
        subtitle_text: "A line"
      }

      assert %MpvProperties{
               position: 0.0,
               duration: 0.0,
               chapters: [],
               chapter: nil,
               audio_tracks: [],
               subtitle_tracks: [],
               aid: 1,
               sid: 2,
               playlist_count: 3,
               playlist_pos: 1,
               subtitle_text: nil
             } = MpvProperties.reset_for_file(mirror)
    end
  end

  describe "parse_track_list/1 — pure parser" do
    test "splits audio and subtitle tracks; converts mpv shape to Track struct" do
      raw = [
        %{
          "id" => 1,
          "type" => "audio",
          "lang" => "jpn",
          "title" => "Stereo",
          "forced" => false
        },
        %{"id" => 2, "type" => "audio", "lang" => "eng"},
        %{"id" => 1, "type" => "sub", "lang" => "eng", "forced" => false},
        %{"id" => 2, "type" => "sub", "lang" => "eng", "forced" => true},
        %{"id" => 3, "type" => "video"}
      ]

      {audio, subs} = MpvProperties.parse_track_list(raw)

      assert length(audio) == 2
      assert length(subs) == 2
      assert Enum.at(audio, 0).index == 1
      assert Enum.at(audio, 0).lang == "jpn"
      assert Enum.at(audio, 0).title == "Stereo"
      assert Enum.at(subs, 1).forced == true
    end

    test "treats empty-string lang as nil" do
      raw = [%{"id" => 1, "type" => "audio", "lang" => ""}]
      {[track], []} = MpvProperties.parse_track_list(raw)
      assert track.lang == nil
    end

    test "normalizes track languages to canonical 3-letter form at the boundary" do
      # mpv reports a mix of 2-letter ("en") and 3-letter ("jpn") codes;
      # all become canonical 3-letter once parsed, so no downstream
      # comparison ever has to reconcile forms.
      raw = [
        %{"id" => 1, "type" => "audio", "lang" => "ja"},
        %{"id" => 2, "type" => "audio", "lang" => "jpn"},
        %{"id" => 1, "type" => "sub", "lang" => "en"},
        %{"id" => 2, "type" => "sub", "lang" => "fre"}
      ]

      {audio, subs} = MpvProperties.parse_track_list(raw)

      assert Enum.map(audio, & &1.lang) == ["jpn", "jpn"]
      assert Enum.map(subs, & &1.lang) == ["eng", "fra"]
    end

    test "detects sdh via mpv's hearing-impaired flag" do
      raw = [%{"id" => 1, "type" => "sub", "lang" => "eng", "hearing-impaired" => true}]
      {[], [track]} = MpvProperties.parse_track_list(raw)
      assert track.sdh == true
    end

    test "detects sdh via title heuristic" do
      raw = [
        %{"id" => 1, "type" => "sub", "lang" => "eng", "title" => "English [SDH]"},
        %{"id" => 2, "type" => "sub", "lang" => "eng", "title" => "Full"}
      ]

      {[], [sdh_track, regular_track]} = MpvProperties.parse_track_list(raw)
      assert sdh_track.sdh == true
      assert regular_track.sdh == false
    end

    test "parses the default disposition flag from the mpv track map" do
      raw = [
        %{"id" => 1, "type" => "sub", "lang" => "eng", "forced" => true, "default" => true},
        %{"id" => 2, "type" => "sub", "lang" => "eng", "default" => false},
        %{"id" => 3, "type" => "sub", "lang" => "spa"}
      ]

      {[], [forced_default, explicit_non_default, absent]} =
        MpvProperties.parse_track_list(raw)

      assert forced_default.default == true
      assert explicit_non_default.default == false
      # Absent flag defaults to false, matching mpv's "no disposition" semantics.
      assert absent.default == false
    end

    test "returns empty lists for non-list input" do
      assert {[], []} = MpvProperties.parse_track_list(nil)
      assert {[], []} = MpvProperties.parse_track_list("garbage")
    end
  end
end
