defmodule MediaCentaur.StorageTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Storage

  describe "parse_df_output/3" do
    test "parses valid df output into usage map" do
      output = """
           Used      Avail
      750000000 250000000
      """

      result = Storage.parse_df_output(output, "/data/movies", "/data/movies")

      assert result == %{
               path: "/data/movies",
               label: "/data/movies",
               used_bytes: 750_000_000,
               total_bytes: 1_000_000_000,
               usage_percent: 75
             }
    end

    test "calculates correct percentage for near-full disk" do
      output = """
           Used      Avail
      950000000  50000000
      """

      result = Storage.parse_df_output(output, "/data", "Image cache")

      assert result.usage_percent == 95
      assert result.label == "Image cache"
    end

    test "handles empty disk (0 used)" do
      output = """
           Used      Avail
             0 1000000000
      """

      result = Storage.parse_df_output(output, "/mnt", "/mnt")

      assert result.usage_percent == 0
      assert result.used_bytes == 0
      assert result.total_bytes == 1_000_000_000
    end

    test "returns nil for malformed output" do
      assert Storage.parse_df_output("", "/x", "x") == nil
      assert Storage.parse_df_output("garbage\nnonsense", "/x", "x") == nil
      assert Storage.parse_df_output("Header\nnot numbers", "/x", "x") == nil
    end

    test "returns nil when header only, no data line" do
      output = """
           Used      Avail
      """

      assert Storage.parse_df_output(output, "/x", "x") == nil
    end
  end

  describe "measure/2" do
    test "returns a valid usage map for /tmp" do
      result = Storage.measure("/tmp", "Temp")

      assert %{
               path: "/tmp",
               label: "Temp",
               used_bytes: used,
               total_bytes: total,
               usage_percent: percent
             } = result

      assert is_integer(used) and used >= 0
      assert is_integer(total) and total > 0
      assert percent >= 0 and percent <= 100
    end

    test "returns nil for nonexistent directory" do
      assert Storage.measure("/nonexistent_path_abc123", "Ghost") == nil
    end
  end
end
