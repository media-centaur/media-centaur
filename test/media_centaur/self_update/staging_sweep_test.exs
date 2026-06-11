defmodule MediaCentaur.SelfUpdate.StagingSweepTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.SelfUpdate.StagingSweep

  setup do
    root = Path.join(System.tmp_dir!(), "staging_sweep_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  defp make_staging_dir(root, name, age_seconds) do
    dir = Path.join(root, name)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "release.tar.gz"), "tar")

    mtime =
      DateTime.utc_now()
      |> DateTime.add(-age_seconds, :second)
      |> DateTime.to_naive()
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.to_erl()

    File.touch!(dir, mtime)
    dir
  end

  test "removes staging dirs older than the max age and keeps fresh ones", %{root: root} do
    stale = make_staging_dir(root, "0.88.0-aaaa", 3 * 24 * 3600)
    fresh = make_staging_dir(root, "0.88.8-bbbb", 60)

    assert StagingSweep.sweep(root, 2 * 24 * 3600) == 1
    refute File.dir?(stale)
    assert File.dir?(fresh)
  end

  test "returns 0 when the staging root does not exist", %{root: root} do
    missing_root = Path.join(root, "never-created")
    assert StagingSweep.sweep(missing_root, 2 * 24 * 3600) == 0
  end

  test "returns 0 for an empty staging root", %{root: root} do
    assert StagingSweep.sweep(root, 2 * 24 * 3600) == 0
  end
end
