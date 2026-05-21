defmodule MediaCentarr.Playback.OverrideCaptureTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Playback.OverrideCapture

  defp state(audio, sub_lang \\ nil, sub_forced \\ false) do
    %{audio_lang: audio, sub_lang: sub_lang, sub_forced: sub_forced}
  end

  describe "compute/2 — no divergence" do
    test "both audio and subs match resolver — :no_change" do
      assert OverrideCapture.compute(state("jpn", "eng"), state("jpn", "eng")) == :no_change
    end

    test "no subs in either — :no_change" do
      assert OverrideCapture.compute(state("eng"), state("eng")) == :no_change
    end

    test "forced flag matches on both sides — :no_change" do
      assert OverrideCapture.compute(state("eng", "eng", true), state("eng", "eng", true)) ==
               :no_change
    end
  end

  describe "compute/2 — audio divergence only" do
    test "user changed audio language" do
      assert {:override, attrs} =
               OverrideCapture.compute(state("jpn", "eng"), state("eng", "eng"))

      assert attrs.audio_lang == "eng"
      assert attrs.subtitle_lang == nil
      assert attrs.subtitles_off == false
    end

    test "user changed audio but kept sub track choice — subs stay 'follow policy'" do
      assert {:override, attrs} = OverrideCapture.compute(state("jpn"), state("eng"))

      assert attrs.audio_lang == "eng"
      assert attrs.subtitle_lang == nil
      assert attrs.subtitles_off == false
    end
  end

  describe "compute/2 — subtitle divergence only" do
    test "user changed subtitle language" do
      assert {:override, attrs} =
               OverrideCapture.compute(state("jpn", "eng"), state("jpn", "spa"))

      assert attrs.audio_lang == nil
      assert attrs.subtitle_lang == "spa"
    end

    test "user enabled subs that resolver chose to hide" do
      assert {:override, attrs} =
               OverrideCapture.compute(state("eng"), state("eng", "eng"))

      assert attrs.subtitle_lang == "eng"
      assert attrs.subtitles_off == false
    end

    test "user disabled subs that resolver wanted shown — subtitles_off=true" do
      assert {:override, attrs} =
               OverrideCapture.compute(state("jpn", "eng"), state("jpn"))

      assert attrs.subtitle_lang == nil
      assert attrs.subtitles_off == true
    end

    test "user changed forced flag on the sub track" do
      assert {:override, attrs} =
               OverrideCapture.compute(state("eng", "eng", false), state("eng", "eng", true))

      assert attrs.subtitle_lang == "eng"
      assert attrs.subtitle_forced == true
    end
  end

  describe "compute/2 — both audio and subs diverge" do
    test "captures both" do
      assert {:override, attrs} =
               OverrideCapture.compute(state("jpn", "eng"), state("fra", "spa"))

      assert attrs.audio_lang == "fra"
      assert attrs.subtitle_lang == "spa"
    end
  end

  describe "compute/2 — toggle-back behaviour" do
    test "user changed then changed back to match resolver — :no_change" do
      # Simulates the user pressing #-#-# (cycle audio away and back) ending
      # on the same state the resolver originally chose.
      assert OverrideCapture.compute(state("jpn", "eng"), state("jpn", "eng")) == :no_change
    end
  end
end
