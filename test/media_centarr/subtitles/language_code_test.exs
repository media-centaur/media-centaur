defmodule MediaCentarr.Subtitles.LanguageCodeTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Subtitles.LanguageCode

  describe "normalize/1" do
    test "passes through valid 2-letter ISO 639-1 codes" do
      assert LanguageCode.normalize("en") == "en"
      assert LanguageCode.normalize("es") == "es"
      assert LanguageCode.normalize("fr") == "fr"
      assert LanguageCode.normalize("ja") == "ja"
    end

    test "maps common ISO 639-2 (3-letter) codes to ISO 639-1 (2-letter)" do
      assert LanguageCode.normalize("eng") == "en"
      assert LanguageCode.normalize("spa") == "es"
      assert LanguageCode.normalize("fre") == "fr"
      assert LanguageCode.normalize("fra") == "fr"
      assert LanguageCode.normalize("ger") == "de"
      assert LanguageCode.normalize("deu") == "de"
      assert LanguageCode.normalize("jpn") == "ja"
      assert LanguageCode.normalize("por") == "pt"
    end

    test "case-insensitive — uppercase input normalises" do
      assert LanguageCode.normalize("EN") == "en"
      assert LanguageCode.normalize("ENG") == "en"
      assert LanguageCode.normalize("Spa") == "es"
    end

    test "returns nil for unknown codes" do
      assert LanguageCode.normalize("xx") == nil
      assert LanguageCode.normalize("zzz") == nil
      assert LanguageCode.normalize("zxx") == nil
    end

    test "returns nil for non-language inputs" do
      assert LanguageCode.normalize("") == nil
      assert LanguageCode.normalize("forced") == nil
      assert LanguageCode.normalize("sdh") == nil
      assert LanguageCode.normalize("default") == nil
    end

    test "returns nil for nil input (so callers can pipe optimistically)" do
      assert LanguageCode.normalize(nil) == nil
    end
  end
end
