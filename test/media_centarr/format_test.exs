defmodule MediaCentarr.FormatTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Format

  describe "format_seconds/1" do
    test "returns 0:00 for nil" do
      assert Format.format_seconds(nil) == "0:00"
    end

    test "formats zero seconds" do
      assert Format.format_seconds(0) == "0:00"
    end

    test "formats seconds under a minute" do
      assert Format.format_seconds(45) == "0:45"
    end

    test "pads single-digit seconds" do
      assert Format.format_seconds(63) == "1:03"
    end

    test "formats minutes and seconds" do
      assert Format.format_seconds(754) == "12:34"
    end

    test "formats hours with padded minutes and seconds" do
      assert Format.format_seconds(3661) == "1:01:01"
    end

    test "formats multi-hour duration" do
      assert Format.format_seconds(7384) == "2:03:04"
    end

    test "truncates fractional seconds" do
      assert Format.format_seconds(90.7) == "1:30"
    end
  end

  describe "short_id/1" do
    test "returns first 8 characters of a UUID" do
      assert Format.short_id("550e8400-e29b-41d4-a716-446655440000") == "550e8400"
    end

    test "handles short strings" do
      assert Format.short_id("abc") == "abc"
    end
  end
end
