defmodule MediaCentaurWeb.Components.Detail.TrackOverrideBadgeTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.MediaTrackOverride
  alias MediaCentaurWeb.Components.Detail.TrackOverrideBadge

  # Rendering and variation coverage lives in
  # `storybook/detail/track_override_badge.story.exs` (enforced by MC0009).
  # This file keeps the pure track-override summary logic, which is domain
  # formatting and belongs in an isolated unit test, not a render assertion.

  describe "track_override_summary/1" do
    test "audio + subtitle override → both segments, audio first, friendly names" do
      override = %MediaTrackOverride{audio_lang: "jpn", subtitle_lang: "eng"}

      assert TrackOverrideBadge.track_override_summary(override) ==
               ["Japanese audio", "English subtitles"]
    end

    test "audio-only override → just the audio segment" do
      override = %MediaTrackOverride{audio_lang: "eng"}

      assert TrackOverrideBadge.track_override_summary(override) == ["English audio"]
    end

    test "subtitles_off override → 'Subtitles off' segment" do
      override = %MediaTrackOverride{subtitles_off: true}

      assert TrackOverrideBadge.track_override_summary(override) == ["Subtitles off"]
    end

    test "forced subtitle override → '(forced)' suffix" do
      override = %MediaTrackOverride{subtitle_lang: "eng", subtitle_forced: true}

      assert TrackOverrideBadge.track_override_summary(override) == ["English subtitles (forced)"]
    end

    test "audio override + subtitles disabled → audio segment then 'Subtitles off'" do
      override = %MediaTrackOverride{audio_lang: "jpn", subtitles_off: true}

      assert TrackOverrideBadge.track_override_summary(override) == ["Japanese audio", "Subtitles off"]
    end

    test "unknown language code falls back to the raw code" do
      override = %MediaTrackOverride{audio_lang: "zzz"}

      assert TrackOverrideBadge.track_override_summary(override) == ["zzz audio"]
    end

    test "empty override (all aspects follow policy) → no segments" do
      assert TrackOverrideBadge.track_override_summary(%MediaTrackOverride{}) == []
    end
  end
end
