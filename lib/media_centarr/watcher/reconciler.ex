defmodule MediaCentarr.Watcher.Reconciler do
  @moduledoc """
  Pure diff calculator for watcher reconcile actions.

  Given the previous and current watch-dir entry lists, computes which
  watcher children need to start, stop, or be replaced (stop + start).
  A replace is emitted when `dir` or `images_dir` changes for an id
  present in both lists. A name-only change is a no-op.
  """

  @type entry :: %{required(String.t()) => String.t() | nil}
  @type diff :: %{
          to_start: [entry()],
          to_stop: [String.t()],
          to_replace: [%{old_dir: String.t(), new: entry()}]
        }

  @spec diff([entry()], [entry()]) :: diff()
  def diff(old_entries, new_entries) do
    old_by_id = Map.new(old_entries, &{&1["id"], &1})
    new_by_id = Map.new(new_entries, &{&1["id"], &1})

    old_ids = MapSet.new(Map.keys(old_by_id))
    new_ids = MapSet.new(Map.keys(new_by_id))

    added = MapSet.difference(new_ids, old_ids)
    removed = MapSet.difference(old_ids, new_ids)
    kept = MapSet.intersection(old_ids, new_ids)

    %{
      to_start: Enum.map(added, &Map.fetch!(new_by_id, &1)),
      to_stop: Enum.map(removed, fn id -> old_by_id[id]["dir"] end),
      to_replace:
        Enum.flat_map(kept, fn id ->
          old = old_by_id[id]
          new = new_by_id[id]

          if old["dir"] != new["dir"] or old["images_dir"] != new["images_dir"] do
            [%{old_dir: old["dir"], new: new}]
          else
            []
          end
        end)
    }
  end
end
