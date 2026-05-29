defmodule MediaCentaurWeb.LibraryFormattersTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.LibraryFormatters

  # --- count_label/2 ---

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
