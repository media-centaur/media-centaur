defmodule MediaCentaur.Watcher.WalkTest do
  @moduledoc """
  The walk's own contract: recursion, pruning, and an unreadable
  directory. What counts as library content is `IgnoreRules`' contract,
  tested in `MediaCentaur.Watcher.IgnoreRulesTest` — the cases here
  assert that the walk *consults* it at both the directory and the file
  level, not that its answers are right.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Watcher.IgnoreRules
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

  defp no_rules, do: IgnoreRules.new([], [])

  describe "walk/3" do
    test "returns files from a flat directory" do
      tree = %{
        "/media" => ["movie.mkv", "trailer.mp4"]
      }

      assert Walk.walk("/media", no_rules(), fs(tree)) ==
               ["/media/movie.mkv", "/media/trailer.mp4"]
    end

    test "recurses into subdirectories" do
      tree = %{
        "/media" => ["movies", "tv"],
        "/media/movies" => ["a.mkv"],
        "/media/tv" => ["show"],
        "/media/tv/show" => ["s01e01.mkv"]
      }

      paths = Walk.walk("/media", no_rules(), fs(tree))

      assert "/media/movies/a.mkv" in paths
      assert "/media/tv/show/s01e01.mkv" in paths
    end

    test "prunes directories matching a name rule (case-insensitive)" do
      tree = %{
        "/media" => ["good", "TRASH"],
        "/media/good" => ["a.mkv"],
        "/media/TRASH" => ["b.mkv"]
      }

      paths = Walk.walk("/media", IgnoreRules.new([], ["trash"]), fs(tree))

      assert paths == ["/media/good/a.mkv"]
    end

    test "prunes directories matching a path rule" do
      tree = %{
        "/media" => ["a.mkv", "images"],
        "/media/images" => ["poster.jpg"]
      }

      paths = Walk.walk("/media", IgnoreRules.new(["/media/images"], []), fs(tree))

      assert paths == ["/media/a.mkv"]
    end

    test "drops files that are not recognised video, without pruning their directory" do
      tree = %{
        "/media" => ["movie.mkv", "poster.jpg", "movie.nfo"]
      }

      assert Walk.walk("/media", no_rules(), fs(tree)) == ["/media/movie.mkv"]
    end

    test "returns empty when directory cannot be read" do
      assert Walk.walk("/missing", no_rules(), fs(%{})) == []
    end

    test "a .staging directory is always invisible — reserved for download-client assembly" do
      # The contract download clients build against (prowlarr-stack's
      # SABnzbd unpacks there): anything inside a directory named
      # `.staging` is in-progress assembly, never library content. Baked
      # in — not dependent on the user's configured name rules.
      tree = %{
        "/media" => ["a.mkv", ".staging"],
        "/media/.staging" => ["Sample.Show.S01E01.1080p.WEB-DL"],
        "/media/.staging/Sample.Show.S01E01.1080p.WEB-DL" => ["episode.mkv"]
      }

      assert Walk.walk("/media", no_rules(), fs(tree)) == ["/media/a.mkv"]
    end

    test "raises if handed a raw list instead of the rule struct" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Walk, :walk, ["/media", ["/media/images"], fs(%{})])
      end
    end
  end
end
