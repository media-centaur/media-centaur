defmodule MediaCentaur.Playback.LanguageContextTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Playback.{Entry, LanguageContext, MpvProperties}
  alias MediaCentaur.Playback.LanguagePolicy

  describe "to_mpv_options/1" do
    test "emits alang/slang/subs-with-matching-audio pairs from the priority args" do
      flags =
        LanguageContext.to_mpv_options(%{
          alang: ["jpn", "eng"],
          slang: ["eng"],
          subs_match_audio: "no",
          disable_subs: false
        })

      assert {"alang", "jpn,eng"} in flags
      assert {"slang", "eng"} in flags
      assert {"subs-with-matching-audio", "no"} in flags
      refute {"sid", "no"} in flags
    end

    # Disabling subs is expressed through `sid` alone. `--sub-visibility=no`
    # is a session-wide render toggle nothing flips back at runtime, so a
    # launch with it made every later subtitle switch in the track menu
    # select a track that never rendered until the player was reopened.
    test "never emits sub-visibility — disabling subs is sid-only" do
      flags =
        LanguageContext.to_mpv_options(%{
          alang: ["eng"],
          slang: [],
          subs_match_audio: "no",
          disable_subs: true
        })

      refute Enum.any?(flags, &match?({"sub-visibility", _}, &1))
      assert {"sid", "no"} in flags
    end

    test "omits alang when alang list is empty" do
      flags =
        LanguageContext.to_mpv_options(%{
          alang: [],
          slang: ["eng"],
          subs_match_audio: "no",
          disable_subs: false
        })

      refute Enum.any?(flags, &match?({"alang", _}, &1))
      assert {"slang", "eng"} in flags
    end

    test "omits slang when slang list is empty (but still emits subs-with-matching-audio)" do
      flags =
        LanguageContext.to_mpv_options(%{
          alang: ["eng"],
          slang: [],
          subs_match_audio: "no",
          disable_subs: false
        })

      refute Enum.any?(flags, &match?({"slang", _}, &1))
      assert {"subs-with-matching-audio", "no"} in flags
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

      {audio, subs} = MpvProperties.parse_track_list(raw)
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

  describe "current_selection/4 — capture-time derivation from the complete track list" do
    setup do
      raw = [
        %{"id" => 1, "type" => "audio", "lang" => "jpn"},
        %{"id" => 2, "type" => "audio", "lang" => "eng"},
        %{"id" => 1, "type" => "sub", "lang" => "eng", "forced" => false},
        %{"id" => 2, "type" => "sub", "lang" => "eng", "forced" => true}
      ]

      {audio, subs} = MpvProperties.parse_track_list(raw)
      %{audio: audio, subs: subs}
    end

    test "resolves audio/subtitle language and forced flag from the supplied indices",
         %{audio: audio, subs: subs} do
      assert LanguageContext.current_selection(1, 1, audio, subs) ==
               %{audio_lang: "jpn", sub_lang: "eng", sub_forced: false}

      assert LanguageContext.current_selection(2, 2, audio, subs) ==
               %{audio_lang: "eng", sub_lang: "eng", sub_forced: true}
    end

    test "a `false`/nil subtitle index (subs off) derives sub_lang nil", %{audio: audio, subs: subs} do
      assert LanguageContext.current_selection(1, false, audio, subs) ==
               %{audio_lang: "jpn", sub_lang: nil, sub_forced: false}

      assert LanguageContext.current_selection(1, nil, audio, subs) ==
               %{audio_lang: "jpn", sub_lang: nil, sub_forced: false}
    end

    # The regression. In production mpv auto-selected the eng sub (sid=1) from
    # our `--slang=eng` launch flag and emitted the `sid` event *before* the
    # subtitle tracks finished demuxing. Deriving the selection language at
    # that instant (from an empty list) yielded nil; deriving it from the
    # complete list (as capture must) yields eng. Same raw sid, different
    # answer depending on which list it's resolved against — so the capture
    # must always resolve against the complete list.
    test "same sid resolves to nil against a stale list but eng against the complete list",
         %{audio: audio, subs: subs} do
      assert LanguageContext.current_selection(1, 1, [], []).sub_lang == nil
      assert LanguageContext.current_selection(1, 1, audio, subs).sub_lang == "eng"
    end
  end

  describe "init/2" do
    test "movie session — owner_type = :movie, original_language from movie" do
      movie = create_movie(%{name: "Sample Movie", original_language: "jpn"})

      context =
        LanguageContext.init(owner_profile_id(), %Entry{
          entity_id: movie.id,
          movie_id: movie.id,
          content_url: "/a.mkv"
        })

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
        LanguageContext.init(owner_profile_id(), %Entry{
          entity_id: tv_series.id,
          episode_id: "fake-episode-uuid",
          content_url: "/a.mkv"
        })

      assert context.owner_type == :tv_series
      assert context.owner_id == tv_series.id
      assert context.original_language == "kor"
    end

    test "normalizes original_language from TMDB's 2-letter form" do
      # TMDB stores ISO 639-1 ("ja"); the context canonicalizes to 3-letter
      # so it matches mpv-reported track languages downstream.
      movie = create_movie(%{name: "Sample Movie", original_language: "ja"})

      context =
        LanguageContext.init(owner_profile_id(), %Entry{
          entity_id: movie.id,
          movie_id: movie.id,
          content_url: "/a.mkv"
        })

      assert context.original_language == "jpn"
    end

    test "loads existing override into context" do
      movie = create_movie(%{name: "Sample Movie", original_language: "jpn"})

      {:ok, _} =
        Library.MediaTrackOverrides.upsert(owner_profile_id(), :movie, movie.id, %{audio_lang: "eng"})

      context =
        LanguageContext.init(owner_profile_id(), %Entry{
          entity_id: movie.id,
          movie_id: movie.id,
          content_url: "/a.mkv"
        })

      assert context.override.audio_lang == "eng"
      # Override prepends to priority list.
      assert hd(context.priority_args.alang) == "eng"

      # Another profile's session does not see this profile's memory.
      ana = create_profile(%{name: "Ana"}).id

      context =
        LanguageContext.init(ana, %Entry{entity_id: movie.id, movie_id: movie.id, content_url: "/a.mkv"})

      assert context.override == nil
      assert hd(context.priority_args.alang) == "jpn"
    end

    test "unsupported entity type (extra) — owner_type = nil, policy still applies" do
      context =
        LanguageContext.init(owner_profile_id(), %Entry{
          entity_id: "any",
          extra_id: "some-extra",
          content_url: "/a.mkv"
        })

      assert context.owner_type == nil
      assert context.owner_id == nil
      assert %LanguagePolicy{} = context.policy
    end
  end
end
