defmodule MediaCentarr.Platform.DriveProbe.BsdDfTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Platform.DriveProbe.BsdDf

  # BSD df output samples come from real macOS / FreeBSD invocations.
  # The Linux CI runner can't actually run BSD df — these tests
  # exercise the parser with captured output via the injectable
  # `cmd_fn` option, the same pattern GnuDfTest uses.

  describe "parse_line/1 — `df -k -P` POSIX-format data rows" do
    # Sample shape:
    #   Filesystem 1024-blocks Used Available Capacity Mounted on
    #   /dev/disk3s1s1 488245288 12345678 100000000 11% /
    #
    # Column meanings (per POSIX `df -P -k`):
    #   $1 = filesystem (source device)
    #   $2 = 1024-byte blocks (total)
    #   $3 = blocks used
    #   $4 = blocks available
    #   $5 = capacity %
    #   $6+ = mount point (may contain spaces, joined back)

    test "parses a typical macOS APFS volume row" do
      line = "/dev/disk3s1s1 488245288 12345678 100000000 11% /"

      assert {:ok, info} = BsdDf.parse_line(line)

      assert info == %{
               device: "disk3s1s1",
               mount_point: "/",
               # 12345678 * 1024
               used_bytes: 12_641_974_272,
               # (12345678 + 100000000) * 1024 = 112345678 * 1024
               total_bytes: 115_041_974_272,
               # round((12345678 / (12345678 + 100000000)) * 100)
               usage_percent: 11
             }
    end

    test "joins multi-segment mount points (spaces)" do
      line = "/dev/disk4s1 100000 50000 50000 50% /Volumes/External Drive"

      assert {:ok, info} = BsdDf.parse_line(line)
      assert info.mount_point == "/Volumes/External Drive"
      assert info.device == "disk4s1"
    end

    test "strips the /dev/ prefix from the device name" do
      line = "/dev/disk3s2 200000 100000 100000 50% /System/Volumes/Data"

      assert {:ok, info} = BsdDf.parse_line(line)
      assert info.device == "disk3s2"
    end

    test "handles devices without /dev/ prefix (synthetic FS)" do
      line = "tmpfs 100 50 50 50% /tmp"

      assert {:ok, info} = BsdDf.parse_line(line)
      assert info.device == "tmpfs"
    end

    test "calculates correct percentage" do
      # 750 blocks used out of 1000 total
      line = "/dev/sda1 1000 750 250 75% /mnt/data"

      assert {:ok, info} = BsdDf.parse_line(line)
      assert info.usage_percent == 75
      assert info.used_bytes == 750 * 1024
      assert info.total_bytes == 1000 * 1024
    end

    test "handles empty disk (0 used)" do
      line = "/dev/sdb1 1000 0 1000 0% /mnt/empty"

      assert {:ok, info} = BsdDf.parse_line(line)
      assert info.usage_percent == 0
      assert info.used_bytes == 0
      assert info.total_bytes == 1000 * 1024
    end

    test "returns :error for malformed lines" do
      assert :error = BsdDf.parse_line("")
      assert :error = BsdDf.parse_line("not enough columns")
      assert :error = BsdDf.parse_line("/dev/sda1 abc 123 456 50% /mnt")
    end
  end

  describe "available_bytes/2 (cmd_fn injected)" do
    test "shells out with `df -k -P` and returns avail × 1024" do
      output = """
      Filesystem 1024-blocks Used Available Capacity Mounted on
      /dev/disk3s1s1 488245288 12345678 100000000 11% /
      """

      cmd_fn = fn "df", ["-k", "-P", "/"], _opts -> {output, 0} end

      assert {:ok, avail} = BsdDf.available_bytes("/", cmd_fn: cmd_fn)
      assert avail == 100_000_000 * 1024
    end

    test "returns :error on non-zero df exit" do
      cmd_fn = fn "df", _args, _opts -> {"df: nope\n", 1} end

      assert :error = BsdDf.available_bytes("/nonexistent", cmd_fn: cmd_fn)
    end

    test "returns :error when output has no data row" do
      cmd_fn = fn "df", _args, _opts ->
        {"Filesystem 1024-blocks Used Available Capacity Mounted on\n", 0}
      end

      assert :error = BsdDf.available_bytes("/", cmd_fn: cmd_fn)
    end
  end

  describe "measure/2 (cmd_fn injected)" do
    test "shells out and parses the first data row" do
      output = """
      Filesystem 1024-blocks Used Available Capacity Mounted on
      /dev/disk3s1s1 488245288 12345678 100000000 11% /
      """

      cmd_fn = fn "df", ["-k", "-P", "/"], _opts -> {output, 0} end

      assert {:ok, info} = BsdDf.measure("/", cmd_fn: cmd_fn)

      assert info == %{
               device: "disk3s1s1",
               mount_point: "/",
               used_bytes: 12_641_974_272,
               total_bytes: 115_041_974_272,
               usage_percent: 11
             }
    end

    test "returns :error when df exits non-zero" do
      cmd_fn = fn "df", _args, _opts -> {"df: no such file\n", 1} end

      assert :error = BsdDf.measure("/nope", cmd_fn: cmd_fn)
    end

    test "passes through the path argument as the third df arg" do
      this = self()

      cmd_fn = fn binary, args, _opts ->
        send(this, {:invoked, binary, args})
        {"Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/x 100 50 50 50% /\n", 0}
      end

      _ = BsdDf.measure("/some/specific/path", cmd_fn: cmd_fn)
      assert_received {:invoked, "df", ["-k", "-P", "/some/specific/path"]}
    end
  end
end
