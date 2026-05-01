defmodule MediaCentarr.Watcher.VideoFileTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.VideoFile

  describe "video?/1" do
    test "matches every recognised extension regardless of case" do
      Enum.each(VideoFile.extensions(), fn ext ->
        assert VideoFile.video?("/media/movies/example" <> ext)
        assert VideoFile.video?("/media/movies/example" <> String.upcase(ext))
      end)
    end

    test "rejects non-video extensions" do
      refute VideoFile.video?("/media/movies/example.txt")
      refute VideoFile.video?("/media/movies/example.srt")
      refute VideoFile.video?("/media/movies/example.nfo")
      refute VideoFile.video?("/media/movies/example.jpg")
    end

    test "rejects extensionless paths" do
      refute VideoFile.video?("/media/movies/no_ext")
    end
  end

  describe "extensions/0" do
    test "returns the canonical lowercase list" do
      assert ".mkv" in VideoFile.extensions()
      assert ".mp4" in VideoFile.extensions()
      assert ".m2ts" in VideoFile.extensions()

      Enum.each(VideoFile.extensions(), fn ext ->
        assert ext == String.downcase(ext)
        assert String.starts_with?(ext, ".")
      end)
    end
  end
end
