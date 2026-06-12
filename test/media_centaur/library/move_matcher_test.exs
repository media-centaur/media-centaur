defmodule MediaCentaur.Library.MoveMatcherTest do
  @moduledoc """
  The pure move-detection decision: is a newly-seen file the same content
  as a file the library already tracks at a different path? Matching is by
  path-relative-to-media-dir plus byte size (see `MoveMatcher` moduledoc).
  No DB, no filesystem — the caller confirms the old path is actually gone.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.MoveMatcher

  defp existing(file_path, media_dir, size),
    do: %{file_path: file_path, media_dir: media_dir, size: size}

  defp new_file(path, media_dir, size), do: %{path: path, media_dir: media_dir, size: size}

  describe "match/2" do
    test "same relative path and size under a new media dir is a move" do
      rows = [existing("/old/Movies/foo/foo.mkv", "/old", 1000)]

      assert {:move, %{file_path: "/old/Movies/foo/foo.mkv"}} =
               MoveMatcher.match(new_file("/new/Movies/foo/foo.mkv", "/new", 1000), rows)
    end

    test "size disambiguates two rows that share a relative path" do
      rows = [
        existing("/a/Movies/foo.mkv", "/a", 1000),
        existing("/c/Movies/foo.mkv", "/c", 2000)
      ]

      assert {:move, %{media_dir: "/c"}} =
               MoveMatcher.match(new_file("/new/Movies/foo.mkv", "/new", 2000), rows)
    end

    test "different relative path is not a move (renames are out of scope)" do
      rows = [existing("/old/Movies/foo.mkv", "/old", 1000)]

      assert :no_match = MoveMatcher.match(new_file("/new/Films/foo.mkv", "/new", 1000), rows)
    end

    test "same relative path but different size is not a move (re-encodes excluded)" do
      rows = [existing("/old/Movies/foo.mkv", "/old", 1000)]

      assert :no_match = MoveMatcher.match(new_file("/new/Movies/foo.mkv", "/new", 2000), rows)
    end

    test "nil stored size falls back to a relative-path-only match (pre-feature rows)" do
      rows = [existing("/old/Movies/foo.mkv", "/old", nil)]

      assert {:move, %{file_path: "/old/Movies/foo.mkv"}} =
               MoveMatcher.match(new_file("/new/Movies/foo.mkv", "/new", 1000), rows)
    end

    test "ambiguous: two rows share relative path AND size, so we bail to no match" do
      rows = [
        existing("/a/Movies/foo.mkv", "/a", 1000),
        existing("/c/Movies/foo.mkv", "/c", 1000)
      ]

      assert :no_match = MoveMatcher.match(new_file("/new/Movies/foo.mkv", "/new", 1000), rows)
    end

    test "no candidates is no match" do
      assert :no_match = MoveMatcher.match(new_file("/new/Movies/foo.mkv", "/new", 1000), [])
    end
  end

  describe "relative_path/2" do
    test "strips the media dir prefix" do
      assert MoveMatcher.relative_path("/mnt/media/Movies/foo.mkv", "/mnt/media") ==
               "Movies/foo.mkv"
    end
  end
end
