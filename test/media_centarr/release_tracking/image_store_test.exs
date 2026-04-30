defmodule MediaCentarr.ReleaseTracking.ImageStoreTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ReleaseTracking.ImageStore

  describe "stale_image?/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "image_store_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "returns true when the file does not exist", %{dir: dir} do
      assert ImageStore.stale_image?(Path.join(dir, "missing.jpg")) == true
    end

    test "returns true for a zero-byte file", %{dir: dir} do
      path = Path.join(dir, "empty.jpg")
      File.write!(path, "")
      assert ImageStore.stale_image?(path) == true
    end

    test "returns true for a file smaller than the stale threshold", %{dir: dir} do
      # Real-world: TMDB w300 backdrops land around 10-20KB. We treat
      # anything under 50KB as stale.
      path = Path.join(dir, "small.jpg")
      File.write!(path, :binary.copy("x", 14_000))
      assert ImageStore.stale_image?(path) == true
    end

    test "returns false for a file at or above the stale threshold", %{dir: dir} do
      # Real-world: TMDB original backdrops land around 100KB-500KB.
      path = Path.join(dir, "big.jpg")
      File.write!(path, :binary.copy("x", 100_000))
      assert ImageStore.stale_image?(path) == false
    end
  end
end
