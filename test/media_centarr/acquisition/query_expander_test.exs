defmodule MediaCentarr.Acquisition.QueryExpanderTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.QueryExpander

  describe "expand/1 — passthrough" do
    test "returns single-element list for plain query" do
      assert QueryExpander.expand("Sample Movie 2049") == {:ok, ["Sample Movie 2049"]}
    end

    test "returns single-element list for empty string" do
      assert QueryExpander.expand("") == {:ok, [""]}
    end

    test "returns single-element list when no braces present" do
      assert QueryExpander.expand("Sample Show S02") == {:ok, ["Sample Show S02"]}
    end
  end

  describe "expand/1 — flat list expansion" do
    test "expands comma-separated list" do
      assert QueryExpander.expand("Sample Show S02E{00,01,02}") ==
               {:ok, ["Sample Show S02E00", "Sample Show S02E01", "Sample Show S02E02"]}
    end

    test "expands single-element list" do
      assert QueryExpander.expand("foo{x}") == {:ok, ["foox"]}
    end

    test "preserves item order" do
      assert QueryExpander.expand("a{c,a,b}d") == {:ok, ["acd", "aad", "abd"]}
    end

    test "allows alphabetic items in a list (not a range)" do
      assert QueryExpander.expand("x{a,b,c}") == {:ok, ["xa", "xb", "xc"]}
    end

    test "preserves whitespace inside list items literally" do
      assert QueryExpander.expand("x{a,b c,d}") == {:ok, ["xa", "xb c", "xd"]}
    end

    test "expands when brace group is at the start" do
      assert QueryExpander.expand("{a,b}foo") == {:ok, ["afoo", "bfoo"]}
    end

    test "expands when brace group is at the end" do
      assert QueryExpander.expand("foo{a,b}") == {:ok, ["fooa", "foob"]}
    end
  end

  describe "expand/1 — numeric range expansion" do
    test "expands two-digit zero-padded range" do
      assert QueryExpander.expand("Sample Show S02E{00-02}") ==
               {:ok, ["Sample Show S02E00", "Sample Show S02E01", "Sample Show S02E02"]}
    end

    test "expands {00-09} with full padding" do
      {:ok, results} = QueryExpander.expand("E{00-09}")

      assert results == [
               "E00",
               "E01",
               "E02",
               "E03",
               "E04",
               "E05",
               "E06",
               "E07",
               "E08",
               "E09"
             ]
    end

    test "single-digit range is not zero-padded" do
      assert QueryExpander.expand("x{1-3}") == {:ok, ["x1", "x2", "x3"]}
    end

    test "two-digit range preserves padding across single-digit values" do
      assert QueryExpander.expand("x{01-10}") ==
               {:ok, ["x01", "x02", "x03", "x04", "x05", "x06", "x07", "x08", "x09", "x10"]}
    end

    test "single-element range" do
      assert QueryExpander.expand("x{05-05}") == {:ok, ["x05"]}
    end

    test "padding width follows the left operand's width" do
      # Left "1" → no padding, even when right is wider
      assert QueryExpander.expand("x{1-12}") ==
               {:ok, ["x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12"]}
    end
  end

  describe "expand/1 — invalid syntax" do
    test "rejects empty braces" do
      assert QueryExpander.expand("x{}") == {:error, :invalid_syntax}
    end

    test "rejects unclosed opening brace" do
      assert QueryExpander.expand("x{a,b") == {:error, :invalid_syntax}
    end

    test "rejects unmatched closing brace" do
      assert QueryExpander.expand("xa,b}") == {:error, :invalid_syntax}
    end

    test "rejects nested braces" do
      assert QueryExpander.expand("x{a{b}c}") == {:error, :invalid_syntax}
    end

    test "rejects multiple brace groups" do
      assert QueryExpander.expand("x{a,b}y{c,d}") == {:error, :invalid_syntax}
    end

    test "rejects alphabetic range" do
      assert QueryExpander.expand("x{a-c}") == {:error, :invalid_syntax}
    end

    test "rejects malformed range with missing right operand" do
      assert QueryExpander.expand("x{1-}") == {:error, :invalid_syntax}
    end

    test "rejects malformed range with missing left operand" do
      assert QueryExpander.expand("x{-9}") == {:error, :invalid_syntax}
    end

    test "rejects descending range" do
      assert QueryExpander.expand("x{9-1}") == {:error, :invalid_syntax}
    end

    test "rejects negative numbers in range" do
      assert QueryExpander.expand("x{-1--3}") == {:error, :invalid_syntax}
    end

    test "rejects mixed range and list (e.g. {1-3,5})" do
      assert QueryExpander.expand("x{1-3,5}") == {:error, :invalid_syntax}
    end
  end
end
