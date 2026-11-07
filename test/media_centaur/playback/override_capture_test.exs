defmodule MediaCentaur.Playback.OverrideCaptureTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.OverrideCapture

  defp state(audio, sub_lang, sub_forced \\ false),
    do: %{audio_lang: audio, sub_lang: sub_lang, sub_forced: sub_forced}

  describe "changes/2 — nothing changed" do
    test "the selection is what was in effect — nothing to save" do
      assert OverrideCapture.changes(state("jpn", "eng"), state("jpn", "eng")) == %{}
      assert OverrideCapture.changes(state("eng", nil), state("eng", nil)) == %{}
      assert OverrideCapture.changes(state("eng", "eng", true), state("eng", "eng", true)) == %{}
    end
  end

  describe "changes/2 — each setting on its own" do
    test "an audio switch saves the audio alone; the subtitles are not touched" do
      assert OverrideCapture.changes(state("jpn", "eng"), state("eng", "eng")) == %{audio_lang: "eng"}
    end

    test "a subtitle switch saves the subtitles alone; the audio is not touched" do
      assert OverrideCapture.changes(state("jpn", "eng"), state("jpn", "spa")) ==
               %{subtitle_lang: "spa", subtitle_forced: false, subtitles_off: false}
    end

    test "turning subtitles on saves the language" do
      assert OverrideCapture.changes(state("eng", nil), state("eng", "eng")) ==
               %{subtitle_lang: "eng", subtitle_forced: false, subtitles_off: false}
    end

    test "turning subtitles off saves them off" do
      assert OverrideCapture.changes(state("jpn", "eng"), state("jpn", nil)) ==
               %{subtitle_lang: nil, subtitle_forced: false, subtitles_off: true}
    end

    test "the forced variant of the same language is a subtitle change" do
      assert OverrideCapture.changes(state("eng", "eng"), state("eng", "eng", true)) ==
               %{subtitle_lang: "eng", subtitle_forced: true, subtitles_off: false}
    end

    test "both switched save both" do
      assert OverrideCapture.changes(state("jpn", "eng"), state("eng", nil)) ==
               %{audio_lang: "eng", subtitle_lang: nil, subtitle_forced: false, subtitles_off: true}
    end

    test "an audio track with no language cannot be remembered, and is not" do
      assert OverrideCapture.changes(state("jpn", "eng"), state(nil, "eng")) == %{}
    end
  end
end
