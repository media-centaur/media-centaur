defmodule MediaCentaur.Platform.WatcherEvents do
  @moduledoc """
  Translates filesystem-watcher backend event vocabularies into the
  domain vocabulary the Watcher pattern-matches on.

  The `file_system` Hex library transparently selects its backend by
  OS — `FSInotify` on Linux, `FSMac` on macOS — and the two emit
  different atom sets for the same domain meaning:

  | Domain meaning      | inotify       | FSEvents     |
  |---------------------|---------------|--------------|
  | File created        | `:created`    | `:created`   |
  | File modified       | `:modified`   | `:modified`  |
  | File deleted        | `:deleted`    | `:removed`   |
  | Volume unmounted    | `:unmounted`  | `:unmount`   |
  | Watched root gone   | (n/a)         | `:rootchanged` |
  | Rescan-required signal | (n/a)      | `:mustscansubdirs`, `:userdropped`, `:kerneldropped`, `:eventidswrapped`, `:renamed` |

  Without translation, `Watcher.handle_info` would silently miss
  deletes and unmounts on macOS — events would arrive under names
  the pattern-match doesn't expect. This module is the only place
  in the codebase that knows the backend vocabularies exist; every
  downstream consumer speaks the domain vocabulary.

  ## Domain vocabulary

      :created | :modified | :deleted | :unmounted | :scan_required

  `:scan_required` is the FSEvents-driven addition. It collapses
  several backend-specific advisory signals (dropped events,
  event-ID rollover, atomic renames) into a single "go look at the
  directory" trigger. The Watcher already knows how to schedule a
  scan in response.

  ## Behaviour

  Unknown atoms (a future `file_system` release adds a new event,
  or an atom we haven't mapped) are silently dropped — the
  Watcher's pattern-match would ignore them anyway, and explicit
  drop keeps the contract uniform. Duplicates are removed,
  preserving first-occurrence order.

  Pure module — no process, no behaviour, just a function.
  """

  @type domain_event :: :created | :modified | :deleted | :unmounted | :scan_required

  @doc """
  Maps a list of backend-emitted event atoms onto the domain
  vocabulary. Unknown atoms are dropped; duplicates collapse.

      iex> MediaCentaur.Platform.WatcherEvents.normalize([:created, :isfile])
      [:created]

      iex> MediaCentaur.Platform.WatcherEvents.normalize([:removed, :isfile])
      [:deleted]

      iex> MediaCentaur.Platform.WatcherEvents.normalize([:userdropped, :kerneldropped])
      [:scan_required]
  """
  @spec normalize([atom()]) :: [domain_event()]
  def normalize(events) when is_list(events) do
    events
    |> Enum.flat_map(&translate/1)
    |> Enum.uniq()
  end

  # --- Domain atoms (identity — Linux atoms + our `:scan_required` invention) ---
  # Idempotence: feeding domain atoms back through normalize/1
  # yields the same atoms. Backends never emit `:scan_required`,
  # so accepting it as input is safe.
  defp translate(:created), do: [:created]
  defp translate(:modified), do: [:modified]
  defp translate(:deleted), do: [:deleted]
  defp translate(:unmounted), do: [:unmounted]
  defp translate(:scan_required), do: [:scan_required]

  # --- FSEvents → domain ---
  defp translate(:removed), do: [:deleted]
  defp translate(:unmount), do: [:unmounted]
  defp translate(:rootchanged), do: [:unmounted]
  defp translate(:renamed), do: [:scan_required]
  defp translate(:mustscansubdirs), do: [:scan_required]
  defp translate(:userdropped), do: [:scan_required]
  defp translate(:kerneldropped), do: [:scan_required]
  defp translate(:eventidswrapped), do: [:scan_required]

  # --- Noise / unknown — silently dropped ---
  # FSEvents emits type markers (`:isfile`, `:isdir`, `:issymlink`),
  # metadata-only changes (`:inodemetamod`, `:finderinfomod`,
  # `:xattrmod`, `:changeowner`), mount notices (`:mount`,
  # `:historydone`), and the "we caused this" loop-avoidance marker
  # (`:ownevent`). None carry domain meaning to Watcher.
  defp translate(_other), do: []
end
