defmodule MediaCentaurWeb.Components.Detail.PlaybackOverrideBadgeTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Library.PlaybackOverride
  alias MediaCentaurWeb.Components.Detail.PlaybackOverrideBadge

  # Rendering and variation coverage lives in
  # `storybook/detail/playback_override_badge.story.exs` (enforced by MC0009).
  # This file keeps the pure track-override summary logic, which is domain
  # formatting and belongs in an isolated unit test, not a render assertion.

  describe "playback_override_summary/1" do
    test "audio + subtitle override → both segments, audio first, friendly names" do
      override = %PlaybackOverride{audio_lang: "jpn", subtitle_lang: "eng"}

      assert PlaybackOverrideBadge.playback_override_summary(override) ==
               ["Japanese audio", "English subtitles"]
    end

    test "audio-only override → just the audio segment" do
      override = %PlaybackOverride{audio_lang: "eng"}

      assert PlaybackOverrideBadge.playback_override_summary(override) == ["English audio"]
    end

    test "subtitles_off override → 'Subtitles off' segment" do
      override = %PlaybackOverride{subtitles_off: true}

      assert PlaybackOverrideBadge.playback_override_summary(override) == ["Subtitles off"]
    end

    test "forced subtitle override → '(forced)' suffix" do
      override = %PlaybackOverride{subtitle_lang: "eng", subtitle_forced: true}

      assert PlaybackOverrideBadge.playback_override_summary(override) == ["English subtitles (forced)"]
    end

    test "audio override + subtitles disabled → audio segment then 'Subtitles off'" do
      override = %PlaybackOverride{audio_lang: "jpn", subtitles_off: true}

      assert PlaybackOverrideBadge.playback_override_summary(override) == [
               "Japanese audio",
               "Subtitles off"
             ]
    end

    test "a remembered picture follows the tracks; a picture on its default is not said" do
      assert PlaybackOverrideBadge.playback_override_summary(%PlaybackOverride{
               audio_lang: "eng",
               fill_width: true
             }) ==
               ["English audio", "Fill width"]

      assert PlaybackOverrideBadge.playback_override_summary(%PlaybackOverride{fill_width: false}) == [
               "Fit"
             ]

      assert PlaybackOverrideBadge.playback_override_summary(%PlaybackOverride{fill_width: nil}) == []
    end

    test "unknown language code falls back to the raw code" do
      override = %PlaybackOverride{audio_lang: "zzz"}

      assert PlaybackOverrideBadge.playback_override_summary(override) == ["zzz audio"]
    end

    test "empty override (all aspects follow policy) → no segments" do
      assert PlaybackOverrideBadge.playback_override_summary(%PlaybackOverride{}) == []
    end
  end
end
