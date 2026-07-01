defmodule MediaCentaurWeb.Components.Acquisition.DownloadStorageTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Acquisition.DownloadStorage

  defp drive(mount_point, role_labels) do
    %{
      mount_point: mount_point,
      device: "/dev/x",
      total_bytes: 1000,
      used_bytes: 100,
      usage_percent: 10,
      roles: Enum.map(role_labels, &%{label: &1, path: mount_point})
    }
  end

  describe "media_dir_drives/1" do
    test "keeps drives that host a media directory" do
      media = drive("/mnt/media", ["Media dir", "Image cache"])
      assert DownloadStorage.media_dir_drives([media]) == [media]
    end

    test "drops drives that only hold the database or an image cache" do
      db_only = drive("/", ["Database", "Image cache"])
      assert DownloadStorage.media_dir_drives([db_only]) == []
    end

    test "keeps only the media-hosting drives from a mixed set" do
      media = drive("/mnt/media", ["Media dir"])
      db_only = drive("/", ["Database", "Image cache"])
      assert DownloadStorage.media_dir_drives([media, db_only]) == [media]
    end

    test "is empty for an empty list" do
      assert DownloadStorage.media_dir_drives([]) == []
    end
  end
end
