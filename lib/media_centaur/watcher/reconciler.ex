defmodule MediaCentaur.Watcher.Reconciler do
  @moduledoc """
  Pure diff calculator for watcher reconcile actions.

  Given the previous and current media-dir entry lists, computes which
  watcher children need to start and which need to stop. An entry's
  directory *is* its identity — `Watcher.Supervisor.reconcile/1` keys on
  `dir` — so a changed directory is a stop plus a start, never an
  in-place replacement.
  """

  @type entry :: %{required(String.t()) => String.t() | nil}
  @type diff :: %{to_start: [entry()], to_stop: [String.t()]}

  @doc """
  Computes start/stop actions for image-directory monitors.

  Each pair is `{media_dir, image_dir}` — `image_dir` is what the
  DirMonitor uses as its registry key, so `to_stop` carries the
  image_dir directly. A change to either field for a given media_dir
  emits one stop and one start (image_dirs are the natural identity
  here — there's no stable "id" the way there is for media_dirs).
  """
  @spec diff_image_monitors([{String.t(), String.t()}], [{String.t(), String.t()}]) :: %{
          to_start: [{String.t(), String.t()}],
          to_stop: [String.t()]
        }
  def diff_image_monitors(old_pairs, new_pairs) do
    old_set = MapSet.new(old_pairs)
    new_set = MapSet.new(new_pairs)

    %{
      to_start: Enum.to_list(MapSet.difference(new_set, old_set)),
      to_stop:
        old_set
        |> MapSet.difference(new_set)
        |> Enum.map(fn {_media_dir, image_dir} -> image_dir end)
    }
  end

  @spec diff([entry()], [entry()]) :: diff()
  def diff(old_entries, new_entries) do
    old_by_id = Map.new(old_entries, &{&1["id"], &1})
    new_by_id = Map.new(new_entries, &{&1["id"], &1})

    old_ids = MapSet.new(Map.keys(old_by_id))
    new_ids = MapSet.new(Map.keys(new_by_id))

    added = MapSet.difference(new_ids, old_ids)
    removed = MapSet.difference(old_ids, new_ids)

    %{
      to_start: Enum.map(added, &Map.fetch!(new_by_id, &1)),
      to_stop: Enum.map(removed, fn id -> old_by_id[id]["dir"] end)
    }
  end
end
