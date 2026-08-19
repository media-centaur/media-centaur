defmodule MediaCentaur.Playback.MpvSessionTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Playback.MpvSession

  describe "launch_target/2" do
    test "scopes the resume position to the first file via per-file option grouping" do
      assert MpvSession.launch_target("/media/a.mkv", 1200.5) ==
               ["--{", "--start=1200.5", "/media/a.mkv", "--}"]
    end

    test "no resume position yields the bare path with no start flag" do
      assert MpvSession.launch_target("/media/a.mkv", 0) == ["/media/a.mkv"]
    end

    # Regression pin for the ADR-062 leak: a bare global --start applies to
    # every playlist entry mpv loads, so an unwatched appended successor
    # would begin at the first episode's resume offset. The flag must only
    # ever appear inside a --{ … --} group.
    test "a resume position never produces a bare global --start" do
      flags = MpvSession.launch_target("/media/a.mkv", 300)
      start_index = Enum.find_index(flags, &String.starts_with?(&1, "--start="))
      assert Enum.at(flags, start_index - 1) == "--{"
      assert List.last(flags) == "--}"
    end
  end
end
