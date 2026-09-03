defmodule MediaCentaur.Playback.TrackOverrideRoundTripTest do
  @moduledoc """
  End-to-end (data-layer) round-trip for per-entity track overrides:

      mid-playback selection  →  OverrideCapture.compute/2
                              →  Library.MediaTrackOverrides.upsert/3
                              →  reload
                              →  TrackResolver.priority_args/3 (next play)

  Each step has its own focused unit test; this chains the public
  functions to prove they compose. The one seam this *cannot* exercise
  is `MpvSession` (the thin mpv wrapper that drives `compute` from real
  property-change events and reads the override at launch) — that is
  validated by the manual real-playback procedure recorded in the
  language-track-preferences campaign (git history).
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Playback.{LanguageContext, LanguagePolicy, OverrideCapture, TrackResolver}

  # English speaker, fallback-only: subtitles only when the audio is in a
  # language they don't understand; forced ("Greedo scene") subs fill the
  # gaps when the audio *is* understood.
  @policy %LanguagePolicy{
    understood_languages: ["eng"],
    audio_priority: ["original", "understood", "any"],
    subtitles_when: "when_audio_not_understood",
    subtitles_language: "understood",
    subtitles_variant: "standard",
    forced_subs: "fill_gaps"
  }

  defp state(audio, sub_lang) do
    %{audio_lang: audio, sub_lang: sub_lang, sub_forced: false}
  end

  test "audio switch (foreign film → dub) is captured and pins the audio on next play" do
    movie = create_movie(%{name: "Round Trip Movie"})

    # Resolver opened the foreign film with original (jpn) audio + eng
    # subs; the user switched the audio track to the eng dub mid-playback.
    {:override, attrs} =
      OverrideCapture.compute(state("jpn", "eng"), state("eng", "eng"))

    {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, attrs)

    override = Library.MediaTrackOverrides.get(:movie, movie.id)
    assert override.audio_lang == "eng"

    # Next play: the override-pinned language leads the --alang priority
    # list ahead of the policy's "original" (jpn).
    args = TrackResolver.priority_args(@policy, override, "jpn")
    assert hd(args.alang) == "eng"
  end

  test "enabling subtitles the resolver hid is captured and forces them on next play" do
    movie = create_movie(%{name: "Round Trip Movie 2"})

    # Understood-audio film: resolver chose eng audio, no subs. The user
    # turned on spa subs (e.g. a language learner).
    {:override, attrs} =
      OverrideCapture.compute(state("eng", nil), state("eng", "spa"))

    {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, attrs)

    override = Library.MediaTrackOverrides.get(:movie, movie.id)
    assert override.subtitle_lang == "spa"
    assert override.subtitles_off == false

    args = TrackResolver.priority_args(@policy, override, "eng")
    assert hd(args.slang) == "spa"
    assert args.disable_subs == false
    assert args.subs_match_audio == "yes"
  end

  test "disabling subtitles the resolver showed is captured and suppresses them on next play" do
    movie = create_movie(%{name: "Round Trip Movie 3"})

    # Foreign-audio film: resolver showed eng subs; the user turned them
    # off (understands enough, or prefers raw audio).
    {:override, attrs} =
      OverrideCapture.compute(state("jpn", "eng"), state("jpn", nil))

    {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, attrs)

    override = Library.MediaTrackOverrides.get(:movie, movie.id)
    assert override.subtitles_off == true

    args = TrackResolver.priority_args(@policy, override, "jpn")
    assert args.slang == []
    assert args.disable_subs == true
  end

  test "auto-selected subs are not poisoned into subtitles_off (Frieren flip-flop regression)" do
    # jpn audio, foreign to an eng speaker → resolver shows the eng sub, and
    # mpv auto-selects it (sid=1) from our --slang=eng launch flag. The bug:
    # the early `sid` event fired before subtitle tracks demuxed, so capture
    # derived sub_lang=nil and persisted subtitles_off=true on EVERY session —
    # even ones that played subs correctly. Capture must derive the current
    # selection from the COMPLETE track list, where sid=1 is the eng sub, so
    # the user's actual selection matches the resolver and nothing is written.
    resolver_choice = state("jpn", "eng")

    {audio_tracks, subtitle_tracks} =
      LanguageContext.parse_track_list([
        %{"id" => 1, "type" => "audio", "lang" => "jpn"},
        %{"id" => 1, "type" => "sub", "lang" => "eng", "forced" => false}
      ])

    current = LanguageContext.current_selection(1, 1, audio_tracks, subtitle_tracks)

    assert OverrideCapture.compute(resolver_choice, current) == :no_change
  end

  test "no divergence captures nothing — the entity keeps following policy" do
    movie = create_movie(%{name: "Round Trip Movie 4"})

    assert OverrideCapture.compute(state("jpn", "eng"), state("jpn", "eng")) == :no_change
    assert Library.MediaTrackOverrides.get(:movie, movie.id) == nil
  end

  test "clearing an override returns the entity to policy resolution" do
    movie = create_movie(%{name: "Round Trip Movie 5"})

    {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, %{audio_lang: "eng"})
    assert :ok = Library.MediaTrackOverrides.clear(:movie, movie.id)

    override = Library.MediaTrackOverrides.get(:movie, movie.id)
    assert override == nil

    # With no override, --alang is the pure policy list: original (jpn)
    # first, then understood (eng).
    args = TrackResolver.priority_args(@policy, override, "jpn")
    assert args.alang == ["jpn", "eng"]
  end
end
