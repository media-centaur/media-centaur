defmodule MediaCentarr.Playback.LanguageContextTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library
  alias MediaCentarr.Playback.LanguageContext
  alias MediaCentarr.Playback.LanguagePolicy

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

      {audio, subs} = LanguageContext.parse_track_list(raw)

      assert length(audio) == 2
      assert length(subs) == 2
      assert Enum.at(audio, 0).index == 1
      assert Enum.at(audio, 0).lang == "jpn"
      assert Enum.at(audio, 0).title == "Stereo"
      assert Enum.at(subs, 1).forced == true
    end

    test "treats empty-string lang as nil" do
      raw = [%{"id" => 1, "type" => "audio", "lang" => ""}]
      {[track], []} = LanguageContext.parse_track_list(raw)
      assert track.lang == nil
    end

    test "detects sdh via mpv's hearing-impaired flag" do
      raw = [%{"id" => 1, "type" => "sub", "lang" => "eng", "hearing-impaired" => true}]
      {[], [track]} = LanguageContext.parse_track_list(raw)
      assert track.sdh == true
    end

    test "detects sdh via title heuristic" do
      raw = [
        %{"id" => 1, "type" => "sub", "lang" => "eng", "title" => "English [SDH]"},
        %{"id" => 2, "type" => "sub", "lang" => "eng", "title" => "Full"}
      ]

      {[], [sdh_track, regular_track]} = LanguageContext.parse_track_list(raw)
      assert sdh_track.sdh == true
      assert regular_track.sdh == false
    end

    test "returns empty lists for non-list input" do
      assert {[], []} = LanguageContext.parse_track_list(nil)
      assert {[], []} = LanguageContext.parse_track_list("garbage")
    end
  end

  describe "to_mpv_flags/1" do
    test "emits --alang/--slang/--sub-visibility/--subs-with-matching-audio from the priority args" do
      flags =
        LanguageContext.to_mpv_flags(%{
          alang: ["jpn", "eng"],
          slang: ["eng"],
          sub_visibility: true,
          subs_match_audio: "exclusive",
          disable_subs: false
        })

      assert "--alang=jpn,eng" in flags
      assert "--slang=eng" in flags
      assert "--sub-visibility=yes" in flags
      assert "--subs-with-matching-audio=exclusive" in flags
      refute "--sid=no" in flags
    end

    test "emits --sid=no when subs disabled (off policy or override)" do
      flags =
        LanguageContext.to_mpv_flags(%{
          alang: ["eng"],
          slang: [],
          sub_visibility: false,
          subs_match_audio: "exclusive",
          disable_subs: true
        })

      assert "--sid=no" in flags
    end

    test "omits --alang when alang list is empty" do
      flags =
        LanguageContext.to_mpv_flags(%{
          alang: [],
          slang: ["eng"],
          sub_visibility: true,
          subs_match_audio: "exclusive",
          disable_subs: false
        })

      refute Enum.any?(flags, &String.starts_with?(&1, "--alang"))
      assert "--slang=eng" in flags
    end

    test "omits --slang when slang list is empty (but still emits subs-with-matching-audio)" do
      flags =
        LanguageContext.to_mpv_flags(%{
          alang: ["eng"],
          slang: [],
          sub_visibility: false,
          subs_match_audio: "exclusive",
          disable_subs: false
        })

      refute Enum.any?(flags, &String.starts_with?(&1, "--slang"))
      assert "--subs-with-matching-audio=exclusive" in flags
    end
  end

  describe "lang_at/2 and forced_at/2" do
    setup do
      raw = [
        %{"id" => 1, "type" => "audio", "lang" => "jpn"},
        %{"id" => 2, "type" => "audio", "lang" => "eng"},
        %{"id" => 1, "type" => "sub", "lang" => "eng", "forced" => false},
        %{"id" => 2, "type" => "sub", "lang" => "eng", "forced" => true}
      ]

      {audio, subs} = LanguageContext.parse_track_list(raw)
      %{audio: audio, subs: subs}
    end

    test "lang_at/2 finds a track's language by mpv id", %{audio: audio, subs: subs} do
      assert LanguageContext.lang_at(2, audio) == "eng"
      assert LanguageContext.lang_at(1, subs) == "eng"
    end

    test "lang_at/2 returns nil when index is nil or not found", %{audio: audio} do
      assert LanguageContext.lang_at(nil, audio) == nil
      assert LanguageContext.lang_at(99, audio) == nil
    end

    test "forced_at/2 returns the forced flag", %{subs: subs} do
      assert LanguageContext.forced_at(1, subs) == false
      assert LanguageContext.forced_at(2, subs) == true
      assert LanguageContext.forced_at(nil, subs) == false
    end
  end

  describe "init/1" do
    test "movie session — owner_type = :movie, original_language from movie" do
      movie = create_movie(%{name: "Sample Movie", original_language: "jpn"})

      context = LanguageContext.init(%{entity_id: movie.id, movie_id: movie.id})

      assert context.owner_type == :movie
      assert context.owner_id == movie.id
      assert context.original_language == "jpn"
      assert %LanguagePolicy{} = context.policy
      assert context.override == nil
      assert context.priority_args.alang == ["jpn", "eng"]
    end

    test "episode session — owner_type = :tv_series, owner_id = series root" do
      tv_series = create_tv_series(%{original_language: "kor"})

      context =
        LanguageContext.init(%{entity_id: tv_series.id, episode_id: "fake-episode-uuid"})

      assert context.owner_type == :tv_series
      assert context.owner_id == tv_series.id
      assert context.original_language == "kor"
    end

    test "loads existing override into context" do
      movie = create_movie(%{name: "Sample Movie", original_language: "jpn"})

      {:ok, _} =
        Library.upsert_media_track_override(:movie, movie.id, %{audio_lang: "eng"})

      context = LanguageContext.init(%{entity_id: movie.id, movie_id: movie.id})

      assert context.override.audio_lang == "eng"
      # Override prepends to priority list.
      assert hd(context.priority_args.alang) == "eng"
    end

    test "unsupported entity type (extra) — owner_type = nil, policy still applies" do
      context = LanguageContext.init(%{entity_id: "any", extra_id: "some-extra"})

      assert context.owner_type == nil
      assert context.owner_id == nil
      assert %LanguagePolicy{} = context.policy
    end
  end
end
