defmodule MediaCentaur.Acquisition.DeliveredFilesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.DeliveredFiles

  defp file(name, size \\ 1_000_000_000), do: %{name: name, size: size}

  describe "problem/1" do
    test "a download with a video file and its usual companions has none" do
      assert DeliveredFiles.problem([
               file("Sample.Show.S01/Sample.Show.S01E01.1080p.WEB-DL.mkv"),
               file("Sample.Show.S01/Sample.Show.S01E02.1080p.WEB-DL.MKV"),
               file("Sample.Show.S01/info.nfo", 2_000),
               file("Sample.Show.S01/Subs/english.srt", 80_000)
             ]) == nil
    end

    test "a download with no video file names what it holds instead" do
      assert DeliveredFiles.problem([file("Sample.Movie.2010.1080p.rar"), file("readme.txt", 300)]) ==
               "The download contains no video file (2 files: .rar, .txt)."
    end

    test "an executable beside the video is a problem — a video release never ships one" do
      assert DeliveredFiles.problem([
               file("Sample.Movie.2010.1080p.mkv"),
               file("codec-setup.EXE", 4_000_000)
             ]) ==
               "The download contains an executable file (codec-setup.EXE)."
    end

    test "a file list the client has not learned yet is not judged" do
      assert DeliveredFiles.problem([]) == nil
    end
  end
end
