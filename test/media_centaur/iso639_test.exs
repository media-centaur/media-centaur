defmodule MediaCentaur.Iso639Test do
  @moduledoc """
  The language-code vocabulary behind track selection, the subtitle label
  UI, and the settings language picker. Every function normalises first,
  so the behaviour worth pinning is that the three ISO forms of one
  language — 2-letter, bibliographic, terminologic — stay interchangeable
  everywhere, and that non-language metadata (`"forced"`, `"sdh"`) never
  masquerades as a language.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Iso639

  describe "normalize/1" do
    test "canonicalises every accepted form to 3-letter ISO 639-2/T" do
      # French is the classic case: "fr" (639-1), "fre" (bibliographic),
      # "fra" (terminologic) are the same language.
      assert Iso639.normalize("fr") == "fra"
      assert Iso639.normalize("fre") == "fra"
      assert Iso639.normalize("fra") == "fra"
    end

    test "is case- and whitespace-insensitive" do
      assert Iso639.normalize("  FR  ") == "fra"
      assert Iso639.normalize("Fre") == "fra"
    end

    test "passes an unknown code through unchanged rather than guessing" do
      assert Iso639.normalize("zzz") == "zzz"
      assert Iso639.normalize("forced") == "forced"
    end

    test "nil normalises to nil" do
      assert Iso639.normalize(nil) == nil
    end
  end

  describe "equal?/2" do
    test "treats every form of the same language as equal" do
      assert Iso639.equal?("fr", "fra")
      assert Iso639.equal?("fre", "fr")
      assert Iso639.equal?("JPN", "ja")
    end

    test "distinguishes different languages" do
      refute Iso639.equal?("fra", "deu")
      refute Iso639.equal?("en", "eng-forced")
    end

    test "two nils are equal, and nil never equals a real code" do
      assert Iso639.equal?(nil, nil)
      refute Iso639.equal?(nil, "eng")
      refute Iso639.equal?("eng", nil)
    end
  end

  describe "to_iso1/1" do
    test "projects a known language to its 2-letter form from any input form" do
      assert Iso639.to_iso1("fra") == "fr"
      assert Iso639.to_iso1("fre") == "fr"
      assert Iso639.to_iso1("fr") == "fr"
    end

    test "returns nil for unknown codes and non-language metadata" do
      assert Iso639.to_iso1("zzz") == nil
      assert Iso639.to_iso1("forced") == nil
      assert Iso639.to_iso1("sdh") == nil
      assert Iso639.to_iso1("") == nil
      assert Iso639.to_iso1(nil) == nil
    end
  end

  describe "display_name/1" do
    test "names a language from any accepted form" do
      assert Iso639.display_name("jpn") == "Japanese"
      assert Iso639.display_name("ja") == "Japanese"
    end

    test "falls back to the code itself when the language is unknown" do
      assert Iso639.display_name("zzz") == "zzz"
    end

    test "nil yields nil" do
      assert Iso639.display_name(nil) == nil
    end
  end

  describe "code_for_name/1" do
    test "resolves an exact display name, case-insensitively" do
      assert Iso639.code_for_name("French") == "fra"
      assert Iso639.code_for_name("french") == "fra"
      assert Iso639.code_for_name("  FRENCH  ") == "fra"
    end

    test "resolves any ISO form of a known code" do
      assert Iso639.code_for_name("fr") == "fra"
      assert Iso639.code_for_name("fre") == "fra"
      assert Iso639.code_for_name("fra") == "fra"
    end

    test "returns nil for input that matches no known language" do
      assert Iso639.code_for_name("Klingon") == nil
      assert Iso639.code_for_name("zzz") == nil
      assert Iso639.code_for_name("") == nil
      assert Iso639.code_for_name("   ") == nil
      assert Iso639.code_for_name(nil) == nil
    end

    test "round-trips against display_name/1 for every language it offers" do
      for {code, name} <- Iso639.all() do
        assert Iso639.code_for_name(name) == code
        assert Iso639.display_name(code) == name
      end
    end
  end

  describe "all/0" do
    test "is sorted by display name" do
      names = Enum.map(Iso639.all(), fn {_code, name} -> name end)

      assert names == Enum.sort(names)
    end

    test "returns canonical codes with non-empty names, and no duplicates" do
      entries = Iso639.all()
      codes = Enum.map(entries, fn {code, _name} -> code end)

      assert codes == Enum.uniq(codes)
      assert Enum.all?(entries, fn {code, name} -> code != "" and name != "" end)
      assert Enum.all?(codes, fn code -> Iso639.normalize(code) == code end)
    end
  end

  describe "find_match/2" do
    test "returns the matching entry in its original form" do
      # The caller cares which of *their* entries matched, so the return
      # is the list's form, not the normalised one.
      assert Iso639.find_match("fra", ["eng", "fre", "deu"]) == "fre"
      assert Iso639.find_match("fr", ["eng", "fra"]) == "fra"
    end

    test "returns the first match when several entries are the same language" do
      assert Iso639.find_match("fra", ["fre", "fr", "fra"]) == "fre"
    end

    test "returns nil when nothing matches" do
      assert Iso639.find_match("fra", ["eng", "deu"]) == nil
      assert Iso639.find_match("fra", []) == nil
      assert Iso639.find_match(nil, ["eng"]) == nil
    end
  end
end
