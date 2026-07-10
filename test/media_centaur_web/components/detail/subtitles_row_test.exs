defmodule MediaCentaurWeb.Components.Detail.SubtitlesRowTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Detail.SubtitlesRow

  # The rendering decision is the per-entry label; the row structure (empty
  # → nothing, separators between entries) is verified by the storybook
  # variations (subtitles_row.story.exs covers [], single, multi, nil, mix).
  describe "split_languages/2" do
    # Releases routinely carry a dozen subtitle languages; the row leads
    # with the ones the user configured as understood (Settings →
    # Language, ISO 639-2) and folds the rest behind a "+N more" reveal.
    test "understood languages surface, the rest hide behind the reveal" do
      languages = ["da", "de", "en", "es", nil]

      assert SubtitlesRow.split_languages(languages, ["eng", "spa"]) ==
               {["en", "es"], ["da", "de", nil]}
    end

    test "cross-form codes match — the policy stores 639-2, tracks carry 639-1" do
      assert SubtitlesRow.split_languages(["en", "ja"], ["jpn"]) == {["ja"], ["en"]}
    end

    test "no understood matches → everything stays behind the reveal" do
      assert SubtitlesRow.split_languages(["da", "de"], ["eng"]) == {[], ["da", "de"]}
    end

    test "no configured languages shows everything up front — a reveal with no lead is pure friction" do
      assert SubtitlesRow.split_languages(["da", "de"], []) == {["da", "de"], []}
    end
  end

  describe "language_label/1" do
    test "an unknown-language sidecar (nil) reads as 'external'" do
      assert SubtitlesRow.language_label(nil) == "external"
    end

    test "a recognised ISO 639-1 code renders verbatim" do
      assert SubtitlesRow.language_label("en") == "en"
      assert SubtitlesRow.language_label("pt") == "pt"
    end
  end
end
