defmodule MediaCentaur.Platform.DriveProbe.GnuDfTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Platform.DriveProbe.GnuDf

  describe "parse_line/1 (lifted from Storage.parse_df_line/1)" do
    test "parses valid df output line into drive info" do
      line = "/dev/sda1      750000000 250000000 /mnt/media"

      assert {:ok, info} = GnuDf.parse_line(line)

      assert info == %{
               device: "sda1",
               mount_point: "/mnt/media",
               used_bytes: 750_000_000,
               total_bytes: 1_000_000_000,
               usage_percent: 75
             }
    end

    test "extracts device basename from full device path" do
      line = "/dev/nvme0n1p2  100000000 900000000 /home"

      assert {:ok, info} = GnuDf.parse_line(line)
      assert info.device == "nvme0n1p2"
    end

    test "handles device paths without /dev/ prefix" do
      line = "tmpfs  500000 500000 /tmp"

      assert {:ok, info} = GnuDf.parse_line(line)
      assert info.device == "tmpfs"
    end

    test "calculates correct percentage for near-full disk" do
      line = "/dev/sda1      950000000  50000000 /mnt/data"

      assert {:ok, info} = GnuDf.parse_line(line)
      assert info.usage_percent == 95
    end

    test "handles empty disk (0 used)" do
      line = "/dev/sdb1              0 1000000000 /mnt/empty"

      assert {:ok, info} = GnuDf.parse_line(line)
      assert info.usage_percent == 0
      assert info.used_bytes == 0
      assert info.total_bytes == 1_000_000_000
    end

    test "returns error for malformed lines" do
      assert :error = GnuDf.parse_line("")
      assert :error = GnuDf.parse_line("not enough columns")
      assert :error = GnuDf.parse_line("/dev/sda1 abc 123 /mnt")
    end
  end

  describe "available_bytes/2 (cmd_fn injected)" do
    test "parses available bytes from df --output=avail output" do
      cmd_fn = fn "df", ["--output=avail", "-B1", "/somepath"], _opts ->
        {"Avail\n1234567890\n", 0}
      end

      assert {:ok, 1_234_567_890} = GnuDf.available_bytes("/somepath", cmd_fn: cmd_fn)
    end

    test "returns :error on non-zero df exit" do
      cmd_fn = fn "df", _args, _opts -> {"df: nope\n", 1} end

      assert :error = GnuDf.available_bytes("/nonexistent", cmd_fn: cmd_fn)
    end

    test "returns :error when output is malformed" do
      cmd_fn = fn "df", _args, _opts -> {"Avail\ngarbage\n", 0} end

      assert :error = GnuDf.available_bytes("/somepath", cmd_fn: cmd_fn)
    end
  end

  describe "measure/2 (cmd_fn injected)" do
    test "shells out and parses the first data row" do
      output =
        "Filesystem 1B-blocks Used Available Mounted on\n/dev/sda1 750000000 250000000 /mnt/media\n"

      cmd_fn = fn "df", _args, _opts -> {output, 0} end

      assert {:ok, info} = GnuDf.measure("/mnt/media", cmd_fn: cmd_fn)

      assert info == %{
               device: "sda1",
               mount_point: "/mnt/media",
               used_bytes: 750_000_000,
               total_bytes: 1_000_000_000,
               usage_percent: 75
             }
    end

    test "returns :error when df exits non-zero" do
      cmd_fn = fn "df", _args, _opts -> {"df: no such file\n", 1} end

      assert :error = GnuDf.measure("/nope", cmd_fn: cmd_fn)
    end

    test "returns :error when df output has no data rows" do
      cmd_fn = fn "df", _args, _opts -> {"Filesystem 1B-blocks Used Available Mounted on\n", 0} end

      assert :error = GnuDf.measure("/mnt/media", cmd_fn: cmd_fn)
    end
  end

  describe "available_bytes/1 (live, no injection)" do
    test "returns available bytes for /tmp on Linux" do
      assert {:ok, avail} = GnuDf.available_bytes("/tmp")
      assert avail > 0
    end

    test "returns :error for a nonexistent path" do
      assert :error = GnuDf.available_bytes("/nonexistent_path_abc123")
    end
  end
end
