defmodule MediaCentaur.StorageTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Storage

  describe "parse_df_line/1" do
    test "parses valid df output line into drive info" do
      line = "/dev/sda1      750000000 250000000 /mnt/media"

      assert {:ok, info} = Storage.parse_df_line(line)

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

      assert {:ok, info} = Storage.parse_df_line(line)
      assert info.device == "nvme0n1p2"
    end

    test "handles device paths without /dev/ prefix" do
      line = "tmpfs  500000 500000 /tmp"

      assert {:ok, info} = Storage.parse_df_line(line)
      assert info.device == "tmpfs"
    end

    test "calculates correct percentage for near-full disk" do
      line = "/dev/sda1      950000000  50000000 /mnt/data"

      assert {:ok, info} = Storage.parse_df_line(line)
      assert info.usage_percent == 95
    end

    test "handles empty disk (0 used)" do
      line = "/dev/sdb1              0 1000000000 /mnt/empty"

      assert {:ok, info} = Storage.parse_df_line(line)
      assert info.usage_percent == 0
      assert info.used_bytes == 0
      assert info.total_bytes == 1_000_000_000
    end

    test "returns error for malformed lines" do
      assert :error = Storage.parse_df_line("")
      assert :error = Storage.parse_df_line("not enough columns")
      assert :error = Storage.parse_df_line("/dev/sda1 abc 123 /mnt")
    end
  end

  describe "group_by_drive/1" do
    test "groups roles under the same mount point" do
      entries = [
        {"/mnt/media/Videos", "Watch dir",
         %{
           device: "sda1",
           mount_point: "/mnt/media",
           used_bytes: 750_000_000,
           total_bytes: 1_000_000_000,
           usage_percent: 75
         }},
        {"/mnt/media/.media-centaur/images", "Image cache",
         %{
           device: "sda1",
           mount_point: "/mnt/media",
           used_bytes: 750_000_000,
           total_bytes: 1_000_000_000,
           usage_percent: 75
         }}
      ]

      [drive] = Storage.group_by_drive(entries)

      assert drive.mount_point == "/mnt/media"
      assert drive.device == "sda1"
      assert drive.used_bytes == 750_000_000
      assert drive.total_bytes == 1_000_000_000
      assert drive.usage_percent == 75

      assert drive.roles == [
               %{label: "Watch dir", path: "/mnt/media/Videos"},
               %{label: "Image cache", path: "/mnt/media/.media-centaur/images"}
             ]
    end

    test "separates entries on different mount points into different drives" do
      entries = [
        {"/mnt/media-1/Videos", "Watch dir",
         %{
           device: "sda1",
           mount_point: "/mnt/media-1",
           used_bytes: 500_000_000,
           total_bytes: 1_000_000_000,
           usage_percent: 50
         }},
        {"/mnt/media-2/Videos", "Watch dir",
         %{
           device: "sdb1",
           mount_point: "/mnt/media-2",
           used_bytes: 200_000_000,
           total_bytes: 500_000_000,
           usage_percent: 40
         }}
      ]

      drives = Storage.group_by_drive(entries)
      assert length(drives) == 2

      mount_points = Enum.map(drives, & &1.mount_point)
      assert "/mnt/media-1" in mount_points
      assert "/mnt/media-2" in mount_points
    end

    test "preserves role ordering within a drive" do
      entries = [
        {"/mnt/media/Videos", "Watch dir",
         %{
           device: "sda1",
           mount_point: "/mnt/media",
           used_bytes: 500_000_000,
           total_bytes: 1_000_000_000,
           usage_percent: 50
         }},
        {"/mnt/media/.media-centaur/images", "Image cache",
         %{
           device: "sda1",
           mount_point: "/mnt/media",
           used_bytes: 500_000_000,
           total_bytes: 1_000_000_000,
           usage_percent: 50
         }},
        {"/mnt/media/data.db", "Database",
         %{
           device: "sda1",
           mount_point: "/mnt/media",
           used_bytes: 500_000_000,
           total_bytes: 1_000_000_000,
           usage_percent: 50
         }}
      ]

      [drive] = Storage.group_by_drive(entries)
      labels = Enum.map(drive.roles, & &1.label)
      assert labels == ["Watch dir", "Image cache", "Database"]
    end

    test "returns empty list for empty input" do
      assert [] = Storage.group_by_drive([])
    end
  end

  describe "available_bytes/1" do
    test "returns available bytes for an existing path" do
      assert {:ok, avail} = Storage.available_bytes("/tmp")
      assert is_integer(avail) and avail > 0
    end

    test "returns :error for a nonexistent path" do
      assert :error = Storage.available_bytes("/nonexistent_path_abc123")
    end
  end
end
