defmodule MediaCentaur.ReviewSeriesRootTest do
  @moduledoc """
  `Review.series_root/1` is the grouping key behind the review queue: files
  sharing a media directory *and* a series root are offered to the user as
  one approve/reject decision. Pure path arithmetic, so it lives here as an
  async unit test rather than inside the DataCase-bound `ReviewTest`.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Review

  defp pending(file_path, media_directory) do
    %{file_path: file_path, media_directory: media_directory}
  end

  describe "series_root/1" do
    test "returns the first path component below the media directory" do
      assert Review.series_root(pending("/media/tv/Sample Show (2001)/Season 1/ep.mkv", "/media/tv")) ==
               "Sample Show (2001)"
    end

    test "a file sitting directly in the media directory is its own root" do
      assert Review.series_root(pending("/media/movies/movie.mkv", "/media/movies")) ==
               "movie.mkv"
    end

    test "groups every episode of one series under the same root" do
      roots =
        Enum.map(
          [
            "/media/tv/Sample Show/Season 1/s01e01.mkv",
            "/media/tv/Sample Show/Season 1/s01e02.mkv",
            "/media/tv/Sample Show/Season 2/s02e01.mkv"
          ],
          &Review.series_root(pending(&1, "/media/tv"))
        )

      assert Enum.uniq(roots) == ["Sample Show"]
    end

    test "keeps different series apart under one media directory" do
      first = Review.series_root(pending("/media/tv/Show A/Season 1/a.mkv", "/media/tv"))
      second = Review.series_root(pending("/media/tv/Show B/Season 1/b.mkv", "/media/tv"))

      refute first == second
    end

    test "falls back to the whole path when the media directory is unknown" do
      # An unclassified file has no directory to be relative to, so it can
      # only group with itself — the full path guarantees that.
      assert Review.series_root(pending("/somewhere/odd/file.mkv", nil)) ==
               "/somewhere/odd/file.mkv"
    end

    test "a path that does not sit under its media directory is not truncated" do
      # `String.replace_prefix/3` leaves a non-matching path alone, so the
      # split yields the absolute path's first component rather than
      # silently mis-grouping the file.
      assert Review.series_root(pending("/other/root/Show/ep.mkv", "/media/tv")) == "/"
    end

    test "a trailing-slash media directory still strips cleanly" do
      assert Review.series_root(pending("/media/tv/Show/ep.mkv", "/media/tv")) == "Show"
    end

    test "deeply nested files still resolve to the top-level series folder" do
      assert Review.series_root(pending("/media/tv/Show/Season 1/Extras/Behind/clip.mkv", "/media/tv")) ==
               "Show"
    end
  end
end
