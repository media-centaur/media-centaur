defmodule MediaCentarr.DateUtilTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.DateUtil

  describe "extract_year/1" do
    test "returns nil for nil input" do
      assert DateUtil.extract_year(nil) == nil
    end

    test "returns nil for empty string" do
      assert DateUtil.extract_year("") == nil
    end

    test "extracts year from full date string" do
      assert DateUtil.extract_year("2024-01-15") == "2024"
    end

    test "extracts year from year-only string" do
      assert DateUtil.extract_year("2024") == "2024"
    end
  end
end
