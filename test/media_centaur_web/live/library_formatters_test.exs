defmodule MediaCentaurWeb.LibraryFormattersTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.LibraryFormatters

  # --- count_label/2 ---

  describe "format_rating/2" do
    test "one-decimal rating with vote count" do
      assert LibraryFormatters.format_rating(7.5, 802) == "★ 7.5 (802 votes)"
    end

    test "thousands of votes abbreviate" do
      assert LibraryFormatters.format_rating(8.234, 12_400) == "★ 8.2 (12.4k votes)"
    end

    test "no votes drops the parenthetical" do
      assert LibraryFormatters.format_rating(6.0, nil) == "★ 6.0"
      assert LibraryFormatters.format_rating(6.0, 0) == "★ 6.0"
    end

    test "nil rating yields nil" do
      assert LibraryFormatters.format_rating(nil, 802) == nil
    end
  end

  describe "count_label/2" do
    test "uses the singular noun for a count of one" do
      assert LibraryFormatters.count_label(1, "title") == "1 title"
    end

    test "pluralizes zero" do
      assert LibraryFormatters.count_label(0, "title") == "0 titles"
    end

    test "pluralizes counts greater than one" do
      assert LibraryFormatters.count_label(324, "movie") == "324 movies"
      assert LibraryFormatters.count_label(2, "show") == "2 shows"
    end
  end
end
