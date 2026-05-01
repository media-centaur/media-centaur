defmodule MediaCentarr.Watcher.WalkTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.ExcludeDirs
  alias MediaCentarr.Watcher.Walk

  defp fs(tree) do
    %{
      ls: fn dir ->
        case Map.fetch(tree, dir) do
          {:ok, entries} -> {:ok, entries}
          :error -> {:error, :enoent}
        end
      end,
      dir?: fn path -> Map.has_key?(tree, path) end
    }
  end

  describe "walk/4" do
    test "returns files from a flat directory" do
      tree = %{
        "/media" => ["movie.mkv", "trailer.mp4"]
      }

      assert Walk.walk("/media", ExcludeDirs.prepare([]), [], fs(tree)) ==
               ["/media/movie.mkv", "/media/trailer.mp4"]
    end

    test "recurses into subdirectories" do
      tree = %{
        "/media" => ["movies", "tv"],
        "/media/movies" => ["a.mkv"],
        "/media/tv" => ["show"],
        "/media/tv/show" => ["s01e01.mkv"]
      }

      paths = Walk.walk("/media", ExcludeDirs.prepare([]), [], fs(tree))

      assert "/media/movies/a.mkv" in paths
      assert "/media/tv/show/s01e01.mkv" in paths
    end

    test "skips directories matching the skip list (case-insensitive)" do
      tree = %{
        "/media" => ["good", "TRASH"],
        "/media/good" => ["a.mkv"],
        "/media/TRASH" => ["b.mkv"]
      }

      paths = Walk.walk("/media", ExcludeDirs.prepare([]), ["trash"], fs(tree))

      assert paths == ["/media/good/a.mkv"]
    end

    test "skips paths under exclude_dirs" do
      tree = %{
        "/media" => ["a.mkv", "images"],
        "/media/images" => ["poster.jpg"]
      }

      excluded = ExcludeDirs.prepare(["/media/images"])
      paths = Walk.walk("/media", excluded, [], fs(tree))

      assert paths == ["/media/a.mkv"]
    end

    test "returns empty when directory cannot be read" do
      assert Walk.walk("/missing", ExcludeDirs.prepare([]), [], fs(%{})) == []
    end
  end
end
