defmodule MediaCentaur.Search.TitleFormTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.TitleForm

  describe "query/1 — what goes to an indexer" do
    test "folds diacritics to the ASCII letters scene names use" do
      # Measured against a live indexer: the accented spelling returned
      # 4 results where the folded one returned 38.
      assert TitleForm.query("Amélie") == "Amelie"
      assert TitleForm.query("Filipiñana") == "Filipinana"
      assert TitleForm.query("Les Misérables") == "Les Miserables"
    end

    test "folds the letters Unicode decomposition leaves behind" do
      assert TitleForm.query("Ødipussi") == "Odipussi"
      assert TitleForm.query("Straße") == "Strasse"
      assert TitleForm.query("Æon Flux") == "Aeon Flux"
    end

    test "strips apostrophes — scene names carry none" do
      assert TitleForm.query("Sample's Movie") == "Samples Movie"
      assert TitleForm.query("Sample's Movie") == "Samples Movie"
    end

    test "collapses whitespace and trims" do
      assert TitleForm.query("  Sample   Movie  ") == "Sample Movie"
    end

    test "leaves an already-plain title alone" do
      assert TitleForm.query("Sample Movie") == "Sample Movie"
    end
  end

  describe "compare/1 — what identity comparison uses" do
    test "folds diacritics so an accented title equals its ASCII release name" do
      assert TitleForm.compare("Amélie") == TitleForm.compare("Amelie")
      assert TitleForm.compare("Amélie") == "amelie"
    end

    test "case-folds, drops apostrophes, and reads punctuation as a separator" do
      assert TitleForm.compare("Sample's Show Twelve") == "samples show twelve"
      assert TitleForm.compare("Samples.Show.Twelve") == "samples show twelve"
      assert TitleForm.compare("SAMPLE - SHOW") == "sample show"
    end

    test "trims the separators left at either end" do
      assert TitleForm.compare(" .Sample Show. ") == "sample show"
    end
  end
end
