defmodule MediaCentaur.Playback.Iso639Test do
  use ExUnit.Case, async: true

  alias MediaCentaur.Playback.Iso639

  describe "normalize/1" do
    test "2-letter ISO 639-1 → 3-letter ISO 639-2/T" do
      assert Iso639.normalize("en") == "eng"
      assert Iso639.normalize("ja") == "jpn"
      assert Iso639.normalize("fr") == "fra"
      assert Iso639.normalize("ko") == "kor"
    end

    test "bibliographic 3-letter → terminologic" do
      assert Iso639.normalize("fre") == "fra"
      assert Iso639.normalize("ger") == "deu"
      assert Iso639.normalize("chi") == "zho"
    end

    test "already-terminologic 3-letter passes through" do
      assert Iso639.normalize("eng") == "eng"
      assert Iso639.normalize("jpn") == "jpn"
    end

    test "case-insensitive" do
      assert Iso639.normalize("EN") == "eng"
      assert Iso639.normalize("Jpn") == "jpn"
    end

    test "whitespace trimmed" do
      assert Iso639.normalize("  en  ") == "eng"
    end

    test "unknown codes pass through unchanged" do
      assert Iso639.normalize("zzz") == "zzz"
      assert Iso639.normalize("klingon") == "klingon"
    end

    test "nil → nil" do
      assert Iso639.normalize(nil) == nil
    end
  end

  describe "equal?/2 — the bug-driver" do
    test "TMDB 2-letter equals mpv 3-letter for the same language" do
      assert Iso639.equal?("en", "eng")
      assert Iso639.equal?("ja", "jpn")
      assert Iso639.equal?("fr", "fra")
      assert Iso639.equal?("ko", "kor")
    end

    test "bibliographic equals terminologic" do
      assert Iso639.equal?("fre", "fra")
      assert Iso639.equal?("ger", "deu")
    end

    test "different languages are not equal" do
      refute Iso639.equal?("en", "ja")
      refute Iso639.equal?("eng", "jpn")
    end

    test "nil never equals anything except nil" do
      assert Iso639.equal?(nil, nil)
      refute Iso639.equal?(nil, "eng")
      refute Iso639.equal?("eng", nil)
    end
  end

  describe "find_match/2" do
    test "returns the original form of the matching entry" do
      assert Iso639.find_match("jpn", ["eng", "spa", "ja"]) == "ja"
      assert Iso639.find_match("en", ["eng"]) == "eng"
    end

    test "nil target or empty list — nil" do
      assert Iso639.find_match(nil, ["eng"]) == nil
      assert Iso639.find_match("eng", []) == nil
    end

    test "no match — nil" do
      assert Iso639.find_match("jpn", ["eng", "spa"]) == nil
    end
  end

  describe "display_name/1" do
    test "canonical 3-letter code → English name" do
      assert Iso639.display_name("eng") == "English"
      assert Iso639.display_name("jpn") == "Japanese"
      assert Iso639.display_name("spa") == "Spanish"
      assert Iso639.display_name("zho") == "Chinese"
    end

    test "2-letter code is normalized before lookup" do
      assert Iso639.display_name("en") == "English"
      assert Iso639.display_name("ja") == "Japanese"
      assert Iso639.display_name("fr") == "French"
    end

    test "bibliographic alternate is normalized before lookup" do
      assert Iso639.display_name("fre") == "French"
      assert Iso639.display_name("ger") == "German"
    end

    test "case-insensitive" do
      assert Iso639.display_name("EN") == "English"
      assert Iso639.display_name("Jpn") == "Japanese"
    end

    test "unknown code falls back to the code itself" do
      assert Iso639.display_name("zzz") == "zzz"
      assert Iso639.display_name("klingon") == "klingon"
    end

    test "nil → nil" do
      assert Iso639.display_name(nil) == nil
    end
  end
end
