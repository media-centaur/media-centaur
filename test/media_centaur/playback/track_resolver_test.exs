defmodule MediaCentaur.Playback.TrackResolverTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.MediaTrackOverride
  alias MediaCentaur.Playback.LanguagePolicy
  alias MediaCentaur.Playback.TrackResolver
  alias MediaCentaur.Playback.TrackResolver.Track

  # ---------------------------------------------------------------------------
  # Track builders — keep test setup readable
  # ---------------------------------------------------------------------------

  defp audio(index, lang, opts \\ []) do
    %Track{
      index: index,
      lang: lang,
      title: Keyword.get(opts, :title),
      forced: false,
      sdh: false
    }
  end

  defp sub(index, lang, opts \\ []) do
    %Track{
      index: index,
      lang: lang,
      title: Keyword.get(opts, :title),
      forced: Keyword.get(opts, :forced, false),
      default: Keyword.get(opts, :default, false),
      sdh: Keyword.get(opts, :sdh, false)
    }
  end

  # ---------------------------------------------------------------------------
  # 9 user experiences (from the brainstorm)
  # ---------------------------------------------------------------------------

  describe "experience: minimalist (never any subs)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "off",
          subtitles_language: "understood",
          subtitles_variant: "standard",
          forced_subs: "never"
        }
      }
    end

    test "japanese anime — picks jpn audio, no subs", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng"), sub(2, "jpn")],
          "jpn"
        )

      assert result.audio_index == 1
      assert result.audio_lang == "jpn"
      assert result.sub_index == nil
    end

    test "english audio — picks eng, still no subs even though sub track exists", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng")],
          "eng"
        )

      assert result.audio_lang == "eng"
      assert result.sub_index == nil
    end
  end

  describe "experience: fallback-only (your default — subs when audio not understood)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "when_audio_not_understood",
          subtitles_language: "understood",
          subtitles_variant: "standard",
          forced_subs: "never"
        }
      }
    end

    test "japanese audio + english subs are shown (audio is foreign)", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng"), sub(2, "jpn")],
          "jpn"
        )

      assert result.audio_lang == "jpn"
      assert result.sub_lang == "eng"
      assert result.sub_forced == false
    end

    test "english audio — no subs shown (audio is understood)", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng")],
          "eng"
        )

      assert result.audio_lang == "eng"
      assert result.sub_index == nil
    end
  end

  describe "experience: fallback + forced (your default + fill_gaps for foreign-dialog scenes)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "when_audio_not_understood",
          subtitles_language: "understood",
          subtitles_variant: "standard",
          forced_subs: "fill_gaps"
        }
      }
    end

    test "english audio + forced subs available — picks forced eng subs (Greedo case)", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng", forced: true), sub(2, "eng")],
          "eng"
        )

      assert result.audio_lang == "eng"
      assert result.sub_lang == "eng"
      assert result.sub_forced == true
    end

    test "japanese audio — main subs win (fill_gaps only fires when audio is understood)", %{
      policy: policy
    } do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "jpn")],
          [sub(1, "eng"), sub(2, "eng", forced: true)],
          "jpn"
        )

      assert result.audio_lang == "jpn"
      assert result.sub_lang == "eng"
      assert result.sub_forced == false
    end

    test "english audio + no forced track available — no subs shown (graceful degrade)", %{
      policy: policy
    } do
      result =
        TrackResolver.resolve(policy, nil, [audio(1, "eng")], [sub(1, "eng")], "eng")

      assert result.sub_index == nil
    end
  end

  describe "experience: captions-always (subs always on in understood language)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "always",
          subtitles_language: "understood",
          subtitles_variant: "standard",
          forced_subs: "fill_gaps"
        }
      }
    end

    test "english audio + english subs (captions-on)", %{policy: policy} do
      result =
        TrackResolver.resolve(policy, nil, [audio(1, "eng")], [sub(1, "eng")], "eng")

      assert result.audio_lang == "eng"
      assert result.sub_lang == "eng"
      assert result.sub_forced == false
    end

    test "japanese audio + english subs (still always)", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "jpn")],
          [sub(1, "eng")],
          "jpn"
        )

      assert result.sub_lang == "eng"
    end
  end

  describe "experience: SDH (deaf / hard-of-hearing)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "always",
          subtitles_language: "understood",
          subtitles_variant: "sdh_preferred",
          forced_subs: "never"
        }
      }
    end

    test "picks the SDH track when present alongside standard", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng"), sub(2, "eng", sdh: true)],
          "eng"
        )

      assert result.sub_index == 2
    end

    test "falls back to standard when no SDH variant available", %{policy: policy} do
      result =
        TrackResolver.resolve(policy, nil, [audio(1, "eng")], [sub(1, "eng")], "eng")

      assert result.sub_index == 1
    end
  end

  describe "experience: language learner (subs in the audio language)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "always",
          subtitles_language: "audio_language",
          subtitles_variant: "standard",
          forced_subs: "never"
        }
      }
    end

    test "japanese audio + japanese subs", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "jpn")],
          [sub(1, "eng"), sub(2, "jpn")],
          "jpn"
        )

      assert result.audio_lang == "jpn"
      assert result.sub_lang == "jpn"
    end
  end

  describe "experience: dub-preferrer (understood audio before original)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["understood", "original", "any"],
          subtitles_when: "when_audio_not_understood",
          subtitles_language: "understood",
          subtitles_variant: "standard",
          forced_subs: "never"
        }
      }
    end

    test "picks english dub even when jpn original exists", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng")],
          "jpn"
        )

      assert result.audio_lang == "eng"
      # Audio is understood, so no subs.
      assert result.sub_index == nil
    end

    test "falls through to original when no dub available", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "jpn")],
          [sub(1, "eng")],
          "jpn"
        )

      assert result.audio_lang == "jpn"
      # Audio is now foreign, so subs are shown.
      assert result.sub_lang == "eng"
    end
  end

  describe "experience: forced-only (subs off, only forced)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "off",
          subtitles_language: "understood",
          subtitles_variant: "standard",
          forced_subs: "always"
        }
      }
    end

    test "english audio — picks forced eng track only", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng"), sub(2, "eng", forced: true)],
          "eng"
        )

      assert result.sub_index == 2
      assert result.sub_forced == true
    end
  end

  describe "experience: polyglot (multiple understood languages, ordered)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng", "spa", "fra"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "when_audio_not_understood",
          subtitles_language: "understood",
          subtitles_variant: "standard",
          forced_subs: "never"
        }
      }
    end

    test "italian audio — no eng subs available — picks spa (next in list)", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "ita")],
          [sub(1, "fra"), sub(2, "spa")],
          "ita"
        )

      assert result.audio_lang == "ita"
      assert result.sub_lang == "spa"
    end

    test "spanish audio — no subs (audio is understood)", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "spa")],
          [sub(1, "eng")],
          "spa"
        )

      assert result.audio_lang == "spa"
      assert result.sub_index == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "ISO 639 language code mismatch — regression coverage" do
    # Discovered 2026-05-22 while inventorying real library: TMDB stores
    # `original_language` as 2-letter ISO 639-1 ("ja", "fr"), mpv's
    # `track-list` reports 3-letter ISO 639-2 ("jpn", "fra") for
    # embedded tracks. Direct string comparison would never match,
    # silently breaking the entire "original audio" branch for every
    # non-English entity. `Iso639.equal?/2` normalizes both forms.
    test "original_language='ja' (TMDB) matches track lang='jpn' (mpv)" do
      result =
        TrackResolver.resolve(
          LanguagePolicy.defaults(),
          nil,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng")],
          # 2-letter, as TMDB returns
          "ja"
        )

      assert result.audio_lang == "jpn"
    end

    test "understood_languages=['en'] matches track lang='eng'" do
      policy = %{LanguagePolicy.defaults() | understood_languages: ["en"]}

      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng")],
          "en"
        )

      assert result.audio_lang == "eng"
      assert result.sub_index == nil
    end

    test "bibliographic 3-letter (fre) matches terminologic (fra)" do
      result =
        TrackResolver.resolve(
          LanguagePolicy.defaults(),
          nil,
          [audio(1, "fre")],
          [sub(1, "eng")],
          "fra"
        )

      assert result.audio_lang == "fre"
    end

    test "SUBTITLE path: understood=['eng'] matches a sub track tagged 'en'" do
      # Real-world regression: a real 4K remux (Pulse) had Japanese audio
      # and an English PGS sub tagged "en". With understood=["eng"] the
      # main-subtitle picker did a direct == against "en" and missed it,
      # so a foreign-audio film showed no subtitles. Audio matched only
      # because original_language and the track were both "ja".
      policy = %{LanguagePolicy.defaults() | understood_languages: ["eng"]}

      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "ja"), audio(2, "it")],
          [sub(1, "en"), sub(2, "it")],
          "ja"
        )

      assert result.audio_lang == "ja"
      assert result.sub_lang == "en"
      assert result.sub_index == 1
    end
  end

  describe "audio resolution edge cases" do
    test "no track matches original — falls through to understood" do
      policy = LanguagePolicy.defaults()

      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng"), audio(2, "fra")],
          [],
          "jpn"
        )

      assert result.audio_lang == "eng"
    end

    test "no track matches original or understood — falls through to 'any'" do
      policy = LanguagePolicy.defaults()

      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "fra"), audio(2, "deu")],
          [],
          "jpn"
        )

      assert result.audio_index == 1
    end

    test "file has no audio tracks at all" do
      policy = LanguagePolicy.defaults()
      result = TrackResolver.resolve(policy, nil, [], [], "jpn")

      assert result.audio_index == nil
      assert result.audio_lang == nil
    end

    test "untagged audio (lang=nil) — still pickable via 'any' fallback" do
      policy = LanguagePolicy.defaults()

      result =
        TrackResolver.resolve(policy, nil, [audio(1, nil)], [], "jpn")

      assert result.audio_index == 1
      assert result.audio_lang == nil
    end
  end

  describe "subtitle resolution edge cases" do
    test "policy wants subs but no track in any understood language — no subs shown" do
      policy = %LanguagePolicy{
        understood_languages: ["eng"],
        audio_priority: ["original", "understood", "any"],
        subtitles_when: "always",
        subtitles_language: "understood",
        subtitles_variant: "standard",
        forced_subs: "never"
      }

      result =
        TrackResolver.resolve(policy, nil, [audio(1, "eng")], [sub(1, "fra")], "eng")

      assert result.sub_index == nil
    end

    test "audio_language sub policy with untagged audio — no subs (can't match unknown language)" do
      policy = %LanguagePolicy{
        understood_languages: ["eng"],
        audio_priority: ["original", "understood", "any"],
        subtitles_when: "always",
        subtitles_language: "audio_language",
        subtitles_variant: "standard",
        forced_subs: "never"
      }

      result =
        TrackResolver.resolve(policy, nil, [audio(1, nil)], [sub(1, "eng")], nil)

      assert result.sub_index == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Overrides
  # ---------------------------------------------------------------------------

  describe "override precedence" do
    test "override pinning audio_lang wins over policy" do
      policy = LanguagePolicy.defaults()
      override = %MediaTrackOverride{audio_lang: "eng"}

      result =
        TrackResolver.resolve(
          policy,
          override,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng")],
          "jpn"
        )

      assert result.audio_lang == "eng"
    end

    test "override pinning subtitle_lang wins over policy's no-subs decision" do
      # Policy would say no subs (eng audio is understood), but the user
      # has explicitly opted to see them for this entity.
      policy = LanguagePolicy.defaults()
      override = %MediaTrackOverride{subtitle_lang: "eng"}

      result =
        TrackResolver.resolve(
          policy,
          override,
          [audio(1, "eng")],
          [sub(1, "eng")],
          "eng"
        )

      assert result.sub_lang == "eng"
    end

    test "override subtitles_off=true wins over policy's want-subs decision" do
      # Policy would show eng subs over jpn audio; user said off for this entity.
      policy = LanguagePolicy.defaults()
      override = %MediaTrackOverride{subtitles_off: true}

      result =
        TrackResolver.resolve(
          policy,
          override,
          [audio(1, "jpn")],
          [sub(1, "eng")],
          "jpn"
        )

      assert result.sub_index == nil
    end

    test "partial override: audio_lang set but subtitle_lang nil — subs still follow policy" do
      policy = LanguagePolicy.defaults()
      override = %MediaTrackOverride{audio_lang: "eng"}

      result =
        TrackResolver.resolve(
          policy,
          override,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng")],
          "jpn"
        )

      assert result.audio_lang == "eng"
      # Audio is now understood per policy → no subs.
      assert result.sub_index == nil
    end

    test "override referencing a language not present in file — falls back to policy" do
      # User had once picked 'fra' for this series, but this episode's file
      # has no French audio. Don't crash and don't pick nothing — apply
      # policy resolution as if there were no override on that field.
      policy = LanguagePolicy.defaults()
      override = %MediaTrackOverride{audio_lang: "fra"}

      result =
        TrackResolver.resolve(
          policy,
          override,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng")],
          "jpn"
        )

      assert result.audio_lang == "jpn"
    end

    test "override forced flag is honoured when picking subtitle track" do
      policy = LanguagePolicy.defaults()
      override = %MediaTrackOverride{subtitle_lang: "eng", subtitle_forced: true}

      result =
        TrackResolver.resolve(
          policy,
          override,
          [audio(1, "eng")],
          [sub(1, "eng"), sub(2, "eng", forced: true)],
          "eng"
        )

      assert result.sub_index == 2
      assert result.sub_forced == true
    end
  end

  # ---------------------------------------------------------------------------
  # Decision log
  # ---------------------------------------------------------------------------

  describe "decision_log" do
    test "logs which audio_priority branch fired" do
      policy = LanguagePolicy.defaults()

      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng")],
          "jpn"
        )

      log = Enum.join(result.decision_log, "\n")
      assert log =~ "original"
      assert log =~ "jpn"
    end

    test "logs override application" do
      policy = LanguagePolicy.defaults()
      override = %MediaTrackOverride{audio_lang: "eng"}

      result =
        TrackResolver.resolve(
          policy,
          override,
          [audio(1, "jpn"), audio(2, "eng")],
          [sub(1, "eng")],
          "jpn"
        )

      log = Enum.join(result.decision_log, "\n")
      assert log =~ "override"
    end
  end

  # ---------------------------------------------------------------------------
  # priority_args/3 — pre-launch mpv args
  # ---------------------------------------------------------------------------

  describe "priority_args/3" do
    test "default policy (fill_gaps) + jpn original — subs_match_audio=forced for native Greedo-scene handling" do
      args = TrackResolver.priority_args(LanguagePolicy.defaults(), nil, "jpn")

      assert args.alang == ["jpn", "eng"]
      assert args.slang == ["eng"]
      assert args.sub_visibility == true
      # Default policy has forced_subs="fill_gaps", so mpv's "forced"
      # value handles the conditional: full subs for foreign audio,
      # forced-only subs when audio is understood.
      assert args.subs_match_audio == "forced"
      assert args.disable_subs == false
    end

    test "when_audio_not_understood + forced_subs=never — subs_match_audio=no" do
      policy = %{
        LanguagePolicy.defaults()
        | subtitles_when: "when_audio_not_understood",
          forced_subs: "never"
      }

      args = TrackResolver.priority_args(policy, nil, "jpn")
      assert args.subs_match_audio == "no"
    end

    test "default policy + eng original — alang yields just eng (no duplicate)" do
      args = TrackResolver.priority_args(LanguagePolicy.defaults(), nil, "eng")

      assert args.alang == ["eng"]
    end

    test "captions-always — subs_match_audio=yes (force-show even when audio matches sub lang)" do
      policy = %{
        LanguagePolicy.defaults()
        | subtitles_when: "always"
      }

      args = TrackResolver.priority_args(policy, nil, "eng")
      assert args.sub_visibility == true
      assert args.subs_match_audio == "yes"
    end

    test "subs off — slang empty, disable_subs=true, visibility off" do
      policy = %{
        LanguagePolicy.defaults()
        | subtitles_when: "off"
      }

      args = TrackResolver.priority_args(policy, nil, "eng")
      assert args.slang == []
      assert args.sub_visibility == false
      assert args.disable_subs == true
    end

    test "polyglot — alang contains the full ordered list" do
      policy = %{
        LanguagePolicy.defaults()
        | understood_languages: ["eng", "spa", "fra"]
      }

      args = TrackResolver.priority_args(policy, nil, "ita")
      assert args.alang == ["ita", "eng", "spa", "fra"]
    end

    test "audio override prepends to alang priority" do
      override = %MediaTrackOverride{audio_lang: "fra"}
      args = TrackResolver.priority_args(LanguagePolicy.defaults(), override, "jpn")

      assert hd(args.alang) == "fra"
    end

    test "subtitle override prepends to slang priority" do
      override = %MediaTrackOverride{subtitle_lang: "spa"}
      args = TrackResolver.priority_args(LanguagePolicy.defaults(), override, "jpn")

      assert hd(args.slang) == "spa"
    end

    test "subtitles_off override forces visibility false and empty slang" do
      override = %MediaTrackOverride{subtitles_off: true}
      args = TrackResolver.priority_args(LanguagePolicy.defaults(), override, "jpn")

      assert args.sub_visibility == false
      assert args.slang == []
    end
  end

  # A release that stamps `forced` onto a full dialogue track *and* leaves
  # it `default` is mislabeled — `forced` ("show only when needed") and
  # `default` ("the main track") are contradictory in intent. The resolver
  # must not surface such a track as a forced fallback, or understood-audio
  # playback comes up with unwanted full subtitles on.
  describe "mislabeled forced+default tracks (fill_gaps)" do
    setup do
      %{
        policy: %LanguagePolicy{
          understood_languages: ["eng"],
          audio_priority: ["original", "understood", "any"],
          subtitles_when: "when_audio_not_understood",
          subtitles_language: "understood",
          subtitles_variant: "standard",
          forced_subs: "fill_gaps"
        }
      }
    end

    test "understood audio + forced AND default sub — distrusted, no subs", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng", forced: true, default: true)],
          "eng"
        )

      assert result.sub_index == nil
      assert result.sub_lang == nil
    end

    test "understood audio + genuine forced (not default) sub — still resolves", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng", forced: true, default: false)],
          "eng"
        )

      assert result.sub_index == 1
      assert result.sub_forced == true
    end

    test "understood audio — genuine forced wins over a mislabeled sibling", %{policy: policy} do
      result =
        TrackResolver.resolve(
          policy,
          nil,
          [audio(1, "eng")],
          [sub(1, "eng", forced: true, default: true), sub(2, "eng", forced: true, default: false)],
          "eng"
        )

      assert result.sub_index == 2
    end
  end

  describe "sid_enforcement/2 — what mpv's sid should be set to" do
    test "skips when no subtitle tracks have demuxed yet" do
      assert TrackResolver.sid_enforcement(%{sub_index: nil}, []) == :skip
      assert TrackResolver.sid_enforcement(%{sub_index: 2}, []) == :skip
    end

    test "disables subs when subs exist but the resolver picked none" do
      subs = [sub(1, "eng", forced: true, default: true)]
      assert TrackResolver.sid_enforcement(%{sub_index: nil}, subs) == {:set, "no"}
    end

    test "sets the resolved sub index when the resolver picked a track" do
      subs = [sub(1, "eng")]
      assert TrackResolver.sid_enforcement(%{sub_index: 1}, subs) == {:set, 1}
    end
  end
end
