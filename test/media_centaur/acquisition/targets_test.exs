defmodule MediaCentaur.Acquisition.TargetsTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Targets

  describe "find_content_path_for/1" do
    test "returns the content_path when the file path is exactly the content_path (single-file release)" do
      create_target(%{content_path: "/media/movies/Some.Release/movie.mkv"})

      assert Targets.find_content_path_for("/media/movies/Some.Release/movie.mkv") ==
               "/media/movies/Some.Release/movie.mkv"
    end

    test "returns the content_path when the file path lives under a folder content_path (pack)" do
      create_target(%{content_path: "/media/tv/Show.S03.WEBRip"})

      assert Targets.find_content_path_for("/media/tv/Show.S03.WEBRip/e01.mkv") ==
               "/media/tv/Show.S03.WEBRip"
    end

    test "does not match a sibling folder with a similar name prefix" do
      create_target(%{content_path: "/media/tv/Show.S03"})

      assert Targets.find_content_path_for("/media/tv/Show.S03.Extended/e01.mkv") == nil
    end

    test "returns nil when no target's content_path relates to the file" do
      create_target(%{content_path: "/media/movies/Unrelated.Release"})

      assert Targets.find_content_path_for("/media/movies/Some.Other.Release/movie.mkv") == nil
    end

    test "returns nil when no target has a content_path at all" do
      create_target(%{content_path: nil})

      assert Targets.find_content_path_for("/media/movies/Whatever/movie.mkv") == nil
    end
  end
end
