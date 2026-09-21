defmodule MediaCentaur.Acquisition.Pursuits.Observations do
  @moduledoc """
  The single pass that records what the download client shows us about a
  target's download.

  One sighting establishes everything at once, so one pass writes it all:

  1. **The stage fact** — `first_seen_in_queue_at`, write-once. Its absence
     after a grab means the client has not shown us the release yet; its
     presence with the download now gone means it left. Absence from the queue
     alone means neither, which is why this column exists.
  2. **The durable file link** — `torrent_hash` and `content_path`, write-once.
     `content_path` can only be read from the live download, and the pipeline
     carries it unchanged into review and the library, so it resolves a
     pursuit's position even after the client drops the finished torrent.
  3. **The observation windows** — `stall_first_seen_at` /
     `zero_seeders_first_seen_at`, the inputs `Policy` decides on.
  4. **The timeline** — `DownloadStarted` on the first sighting,
     `HealthChanged` on every later transition. Story beats, not heartbeats:
     an unchanged tick writes nothing at all.

  ## Why the target owns all of it

  A target is one grab of one *release*, and a release is one download at the
  client — a season pack covers 38 units but is still one target
  (`Pursuits.TargetUnit`). Observing per unit multiplied every timeline event
  by the unit count; observing per pursuit (the correction that overshot)
  tracked only one of a composite's several concurrent torrents and could not
  say which torrent an event was about. The target is the level at which
  "the download" is a single thing.

  ## Pairing

  `QueueMatcher.find_item/4` — the same predicate the index pairing, the
  status derivation and `Snapshots` use. It matches on the infohash when the
  target carries one and falls back to prefix-tolerant title containment when
  it doesn't, which is how a no-hash usenet grab pairs until the hash is
  backfilled from this very pass.

  ## When nothing is written

  A `:unknown` queue (client unreachable) is a no-op: we don't penalise the
  user for an outage. A target absent from *this* tick's snapshot keeps its
  last observation — a transient absence must not synthesize a transition.
  A `content_path` the host can't stat is dropped rather than pinned, because
  a docker-namespace path (SABnzbd's `/downloads/completed/…`) can never match
  a library path and would poison a write-once slot forever.
  """

  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.{DownloadStarted, HealthChanged}
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.{QueueMatcher, Target}
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.Repo

  @doc """
  Observes one target against a queue snapshot. Returns the refreshed target.
  Idempotent: re-running against the same snapshot writes nothing and emits
  nothing.
  """
  @spec observe!(Pursuit.t(), Target.t() | nil, [QueueItem.t()] | :unknown, DateTime.t()) ::
          Target.t() | nil
  def observe!(pursuit, target, queue, now)

  def observe!(%Pursuit{}, nil, _queue, _now), do: nil
  def observe!(%Pursuit{}, %Target{} = target, :unknown, _now), do: target

  def observe!(%Pursuit{} = pursuit, %Target{} = target, queue, %DateTime{} = now) when is_list(queue) do
    case QueueMatcher.find_item(queue, target.torrent_hash, target.release_title) do
      nil -> target
      %QueueItem{} = item -> record!(pursuit, target, item, now)
    end
  end

  defp record!(%Pursuit{} = pursuit, %Target{} = target, %QueueItem{} = item, now) do
    pursuit
    |> transition_event(target, item, now)
    |> emit()

    target
    |> Target.observation_changeset(%{
      torrent_hash: item.id,
      content_path: usable_content_path(item.content_path),
      first_seen_in_queue_at: now,
      last_queue_state: stringify(item.state),
      last_queue_health: stringify(item.health)
    })
    |> Target.window_changeset(
      stalling: stalling?(item),
      no_seeders: no_seeders?(item),
      now: now
    )
    |> save()
  end

  # The pass runs on every queue snapshot; a steady download whose telemetry
  # has not moved must not write a row per tick.
  defp save(%Ecto.Changeset{changes: changes} = changeset) when map_size(changes) == 0,
    do: changeset.data

  defp save(changeset), do: Repo.update!(changeset)

  # A dockerized client reports paths in its own mount namespace (SABnzbd's
  # history `storage`: /downloads/completed/…). Pinning a path this host can't
  # see poisons the write-once slot with a value that can never match a library
  # path — worse than nil, which leaves the capture retrying until a real path
  # (or the name-match landing via InboundListener) arrives.
  defp usable_content_path(nil), do: nil

  defp usable_content_path(path) when is_binary(path) do
    if File.exists?(path), do: path
  end

  defp stalling?(%QueueItem{state: :stalled}), do: true
  defp stalling?(%QueueItem{health: health}) when health in [:soft_stall, :frozen], do: true
  defp stalling?(%QueueItem{}), do: false

  # qBittorrent's `stalledDL` means "no peers / no progress" — the strongest
  # "definitely dead release" signal available without a seeder count on
  # `QueueItem`.
  defp no_seeders?(%QueueItem{state: :stalled}), do: true
  defp no_seeders?(%QueueItem{}), do: false

  # Stringify only real values — `Atom.to_string(nil)` is the string "nil",
  # which once leaked into payloads and UI copy as the literal word.
  defp stringify(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp stringify(_value), do: nil

  defp transition_event(%Pursuit{} = pursuit, %Target{} = target, %QueueItem{} = item, now) do
    to_state = stringify(item.state)
    to_health = stringify(item.health)
    from_state = target.last_queue_state
    from_health = target.last_queue_health

    cond do
      is_nil(from_state) and is_nil(from_health) and not (is_nil(to_state) and is_nil(to_health)) ->
        %DownloadStarted{
          pursuit_id: pursuit.id,
          pursuit_title: pursuit.title,
          occurred_at: now,
          client: client_name(item),
          infohash: item.id
        }

      from_state != to_state or from_health != to_health ->
        %HealthChanged{
          pursuit_id: pursuit.id,
          pursuit_title: pursuit.title,
          occurred_at: now,
          from_state: from_state,
          to_state: to_state,
          from_health: from_health,
          to_health: to_health
        }

      true ->
        nil
    end
  end

  # Payload identifier (matches the config type strings), not display copy.
  defp client_name(%QueueItem{protocol: :usenet}), do: "sabnzbd"
  defp client_name(%QueueItem{}), do: "qbittorrent"

  defp emit(nil), do: :ok
  defp emit(event), do: Events.record(event)
end
