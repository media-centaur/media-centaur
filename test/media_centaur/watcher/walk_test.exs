defmodule MediaCentaur.Watcher.WalkTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Watcher.ExcludeDirs
  alias MediaCentaur.Watcher.Walk

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

    test "a .staging directory is always invisible — reserved for download-client assembly" do
      # The contract download clients build against (prowlarr-stack's
      # SABnzbd unpacks there): anything inside a directory named
      # `.staging` is in-progress assembly, never library content. Baked
      # in — not dependent on the user's configured skip list.
      tree = %{
        "/media" => ["a.mkv", ".staging"],
        "/media/.staging" => ["Sample.Show.S01E01.1080p.WEB-DL"],
        "/media/.staging/Sample.Show.S01E01.1080p.WEB-DL" => ["episode.mkv"]
      }

      assert Walk.walk("/media", ExcludeDirs.prepare([]), [], fs(tree)) == ["/media/a.mkv"]
    end
  end

  describe "in_skip_dir?/2" do
    test "true when any parent component is a configured skip dir (case-insensitive)" do
      assert Walk.in_skip_dir?("/media/TRASH/b.mkv", ["trash"])
      refute Walk.in_skip_dir?("/media/good/a.mkv", ["trash"])
    end

    test "the file's own name never matches — only parent components" do
      refute Walk.in_skip_dir?("/media/trash", ["trash"])
    end

    test ".staging parents match without any configured skip list" do
      assert Walk.in_skip_dir?("/media/.staging/Sample.Show/episode.mkv", [])
      refute Walk.in_skip_dir?("/media/show/episode.mkv", [])
    end
  end
end
