defmodule MediaCentarr.Playback.MpvLogReaderTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Playback.MpvLogReader

  @moduletag :tmp_dir

  describe "tail_lines/2 — pure" do
    test "returns last N lines of a multi-line binary" do
      content = """
      line 1
      line 2
      line 3
      line 4
      line 5
      """

      assert MpvLogReader.tail_lines(content, 2) == ["line 4", "line 5"]
    end

    test "returns all lines when count exceeds available" do
      assert MpvLogReader.tail_lines("a\nb\n", 10) == ["a", "b"]
    end

    test "returns [] for empty content" do
      assert MpvLogReader.tail_lines("", 5) == []
    end

    test "handles content with no trailing newline" do
      assert MpvLogReader.tail_lines("alpha\nbeta\ngamma", 2) == ["beta", "gamma"]
    end

    test "drops blank lines" do
      assert MpvLogReader.tail_lines("a\n\nb\n\n", 5) == ["a", "b"]
    end
  end

  describe "read_tail/2 — filesystem" do
    test "reads tail from an existing file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "mpv.log")
      File.write!(path, "first\nsecond\nthird\n")

      assert MpvLogReader.read_tail(path, 2) == ["second", "third"]
    end

    test "returns [] for missing file", %{tmp_dir: tmp_dir} do
      assert MpvLogReader.read_tail(Path.join(tmp_dir, "absent.log"), 5) == []
    end

    test "returns [] for empty file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "empty.log")
      File.write!(path, "")

      assert MpvLogReader.read_tail(path, 5) == []
    end

    test "returns [] for nil path" do
      assert MpvLogReader.read_tail(nil, 5) == []
    end
  end

  describe "fallback_tail/3" do
    test "prefers a non-empty port tail and ignores the log file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "mpv.log")
      File.write!(path, "log-file-line\n")

      assert MpvLogReader.fallback_tail(["port-line"], path, 5) == ["port-line"]
    end

    test "falls back to the log file when port tail is empty", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "mpv.log")
      File.write!(path, "first\nsecond\n")

      assert MpvLogReader.fallback_tail([], path, 5) == ["first", "second"]
    end

    test "returns [] when port tail is empty and log file is missing", %{tmp_dir: tmp_dir} do
      assert MpvLogReader.fallback_tail([], Path.join(tmp_dir, "absent.log"), 5) == []
    end

    test "returns [] when port tail is empty and path is nil" do
      assert MpvLogReader.fallback_tail([], nil, 5) == []
    end
  end
end
