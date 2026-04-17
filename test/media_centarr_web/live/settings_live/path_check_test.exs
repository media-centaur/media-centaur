defmodule MediaCentarrWeb.Live.SettingsLive.PathCheckTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Live.SettingsLive.PathCheck

  @tmp_dir System.tmp_dir!()

  setup do
    # Unique temp scratch space, cleaned up on test exit.
    dir = Path.join(@tmp_dir, "path_check_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  describe "check/2 — nil and empty paths" do
    test "returns :missing for nil" do
      assert PathCheck.check(nil, :file) == :missing
      assert PathCheck.check(nil, :directory) == :missing
      assert PathCheck.check(nil, :executable) == :missing
    end

    test "returns :missing for an empty string" do
      assert PathCheck.check("", :file) == :missing
      assert PathCheck.check("   ", :file) == :missing
    end
  end

  describe "check/2 with kind :file" do
    test "returns :ok when a regular file exists", %{dir: dir} do
      path = Path.join(dir, "thing.txt")
      File.write!(path, "hi")
      assert PathCheck.check(path, :file) == :ok
    end

    test "returns :missing when the file does not exist", %{dir: dir} do
      assert PathCheck.check(Path.join(dir, "nope.txt"), :file) == :missing
    end

    test "returns :wrong_kind when the path is a directory", %{dir: dir} do
      assert PathCheck.check(dir, :file) == :wrong_kind
    end
  end

  describe "check/2 with kind :directory" do
    test "returns :ok for an existing directory", %{dir: dir} do
      assert PathCheck.check(dir, :directory) == :ok
    end

    test "returns :missing for a nonexistent directory", %{dir: dir} do
      assert PathCheck.check(Path.join(dir, "gone"), :directory) == :missing
    end

    test "returns :wrong_kind when the path is a regular file", %{dir: dir} do
      path = Path.join(dir, "a-file")
      File.write!(path, "hi")
      assert PathCheck.check(path, :directory) == :wrong_kind
    end
  end

  describe "check/2 with kind :executable" do
    test "returns :ok when the file exists and is executable", %{dir: dir} do
      path = Path.join(dir, "runnable")
      File.write!(path, "#!/bin/sh\n")
      File.chmod!(path, 0o755)
      assert PathCheck.check(path, :executable) == :ok
    end

    test "returns :not_executable when the file exists but lacks exec bit", %{dir: dir} do
      path = Path.join(dir, "not-exec")
      File.write!(path, "data")
      File.chmod!(path, 0o644)
      assert PathCheck.check(path, :executable) == :not_executable
    end

    test "returns :missing when the file does not exist", %{dir: dir} do
      assert PathCheck.check(Path.join(dir, "gone"), :executable) == :missing
    end
  end

  describe "ok?/1" do
    test "returns true only for :ok" do
      assert PathCheck.ok?(:ok)
      refute PathCheck.ok?(:missing)
      refute PathCheck.ok?(:wrong_kind)
      refute PathCheck.ok?(:not_executable)
    end
  end

  describe "label/1" do
    test "maps each result to a user-facing string" do
      assert PathCheck.label(:ok) == "Found"
      assert PathCheck.label(:missing) =~ "not found"
      assert PathCheck.label(:wrong_kind) =~ "wrong kind"
      assert PathCheck.label(:not_executable) =~ "not executable"
    end
  end
end
