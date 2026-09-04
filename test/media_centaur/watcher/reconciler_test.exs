defmodule MediaCentaur.Watcher.ReconcilerTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Watcher.Reconciler

  # `Watcher.Supervisor.reconcile/1` builds entries exactly this way: the
  # directory is the id, and images_dir/name are always nil.
  defp entry(dir) do
    %{"id" => dir, "dir" => dir, "images_dir" => nil, "name" => nil}
  end

  test "no change returns no actions" do
    list = [entry("/mnt/a")]
    assert %{to_start: [], to_stop: []} = Reconciler.diff(list, list)
  end

  test "new entry → to_start" do
    assert %{to_start: [%{"dir" => "/mnt/b"}], to_stop: []} =
             Reconciler.diff([], [entry("/mnt/b")])
  end

  test "removed entry → to_stop" do
    assert %{to_start: [], to_stop: ["/mnt/a"]} =
             Reconciler.diff([entry("/mnt/a")], [])
  end

  test "an edited directory is a stop plus a start, not a replacement" do
    result = Reconciler.diff([entry("/mnt/a")], [entry("/mnt/a2")])

    assert Enum.map(result.to_start, & &1["dir"]) == ["/mnt/a2"]
    assert result.to_stop == ["/mnt/a"]
  end

  test "mixed: add + remove + edit + no-op in one diff" do
    old = [entry("/mnt/a"), entry("/mnt/b"), entry("/mnt/c")]
    new = [entry("/mnt/a"), entry("/mnt/b2"), entry("/mnt/d")]

    result = Reconciler.diff(old, new)
    assert Enum.sort(Enum.map(result.to_start, & &1["dir"])) == ["/mnt/b2", "/mnt/d"]
    assert Enum.sort(result.to_stop) == ["/mnt/b", "/mnt/c"]
  end

  describe "diff_image_monitors/2" do
    test "no change returns empty actions" do
      pairs = [{"/mnt/a", "/mnt/ssd/images-a"}]
      assert %{to_start: [], to_stop: []} = Reconciler.diff_image_monitors(pairs, pairs)
    end

    test "new pair → to_start" do
      old = []
      new = [{"/mnt/a", "/mnt/ssd/images-a"}]

      assert %{to_start: [{"/mnt/a", "/mnt/ssd/images-a"}], to_stop: []} =
               Reconciler.diff_image_monitors(old, new)
    end

    test "removed pair → to_stop carries image_dir" do
      old = [{"/mnt/a", "/mnt/ssd/images-a"}]
      new = []

      assert %{to_start: [], to_stop: ["/mnt/ssd/images-a"]} =
               Reconciler.diff_image_monitors(old, new)
    end

    test "image_dir changed for the same media_dir → stop old + start new" do
      old = [{"/mnt/a", "/mnt/ssd/images-a"}]
      new = [{"/mnt/a", "/mnt/nvme/images-a"}]

      assert %{
               to_start: [{"/mnt/a", "/mnt/nvme/images-a"}],
               to_stop: ["/mnt/ssd/images-a"]
             } = Reconciler.diff_image_monitors(old, new)
    end
  end
end
