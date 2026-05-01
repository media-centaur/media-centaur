defmodule MediaCentarr.Watcher.DeletionBufferTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.DeletionBuffer

  describe "new/0" do
    test "starts empty" do
      buffer = DeletionBuffer.new()
      assert DeletionBuffer.empty?(buffer)
      assert DeletionBuffer.paths(buffer) == []
    end
  end

  describe "add/3" do
    test "records a path/watch_dir pair" do
      buffer = DeletionBuffer.add(DeletionBuffer.new(), "/media/movies/a.mkv", "/media/movies")

      refute DeletionBuffer.empty?(buffer)
      assert DeletionBuffer.paths(buffer) == ["/media/movies/a.mkv"]
    end

    test "deduplicates the same path" do
      buffer =
        DeletionBuffer.new()
        |> DeletionBuffer.add("/media/a.mkv", "/media")
        |> DeletionBuffer.add("/media/a.mkv", "/media")

      assert length(DeletionBuffer.paths(buffer)) == 1
    end

    test "accumulates distinct paths" do
      buffer =
        DeletionBuffer.new()
        |> DeletionBuffer.add("/media/a.mkv", "/media")
        |> DeletionBuffer.add("/media/b.mkv", "/media")
        |> DeletionBuffer.add("/media/c.mkv", "/media")

      assert length(DeletionBuffer.paths(buffer)) == 3
    end
  end

  describe "reset/1" do
    test "returns an empty buffer" do
      buffer =
        DeletionBuffer.new()
        |> DeletionBuffer.add("/media/a.mkv", "/media")
        |> DeletionBuffer.reset()

      assert DeletionBuffer.empty?(buffer)
    end
  end

  describe "empty?/1" do
    test "true for fresh buffer" do
      assert DeletionBuffer.empty?(DeletionBuffer.new())
    end

    test "false after add" do
      buffer = DeletionBuffer.add(DeletionBuffer.new(), "/p", "/wd")
      refute DeletionBuffer.empty?(buffer)
    end
  end
end
