defmodule MediaCentarr.Watcher.ReconcilerTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.Reconciler

  defp entry(id, dir, opts \\ []) do
    %{
      "id" => id,
      "dir" => dir,
      "images_dir" => opts[:images_dir],
      "name" => opts[:name]
    }
  end

  test "no change returns no actions" do
    list = [entry("a", "/mnt/a")]
    assert %{to_start: [], to_stop: [], to_replace: []} = Reconciler.diff(list, list)
  end

  test "new entry → to_start" do
    assert %{to_start: [%{"dir" => "/mnt/b"}], to_stop: [], to_replace: []} =
             Reconciler.diff([], [entry("b", "/mnt/b")])
  end

  test "removed entry → to_stop" do
    assert %{to_start: [], to_stop: ["/mnt/a"], to_replace: []} =
             Reconciler.diff([entry("a", "/mnt/a")], [])
  end

  test "dir changed → to_replace" do
    old = [entry("a", "/mnt/a")]
    new = [entry("a", "/mnt/a2")]

    assert %{
             to_start: [],
             to_stop: [],
             to_replace: [%{old_dir: "/mnt/a", new: %{"dir" => "/mnt/a2"}}]
           } = Reconciler.diff(old, new)
  end

  test "images_dir changed → to_replace" do
    old = [entry("a", "/mnt/a", images_dir: nil)]
    new = [entry("a", "/mnt/a", images_dir: "/mnt/ssd")]

    assert %{to_replace: [%{old_dir: "/mnt/a", new: %{"images_dir" => "/mnt/ssd"}}]} =
             Reconciler.diff(old, new)
  end

  test "name-only change is a no-op" do
    old = [entry("a", "/mnt/a", name: nil)]
    new = [entry("a", "/mnt/a", name: "Movies")]
    assert %{to_start: [], to_stop: [], to_replace: []} = Reconciler.diff(old, new)
  end

  test "mixed: add + remove + replace + no-op in one diff" do
    old = [entry("a", "/mnt/a"), entry("b", "/mnt/b"), entry("c", "/mnt/c")]
    new = [entry("a", "/mnt/a"), entry("b", "/mnt/b2"), entry("d", "/mnt/d")]

    result = Reconciler.diff(old, new)
    assert Enum.map(result.to_start, & &1["dir"]) == ["/mnt/d"]
    assert result.to_stop == ["/mnt/c"]
    assert [%{old_dir: "/mnt/b", new: %{"dir" => "/mnt/b2"}}] = result.to_replace
  end
end
