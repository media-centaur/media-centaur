defmodule MediaCentaur.Library.MediaInfo do
  @moduledoc """
  Derived technical metadata for files on disk — codec, resolution,
  duration, audio-track summary — read out of the container by ffprobe
  and stored one row per `FilePresence` (ADR-057).

  The data is **recomputable**, which shapes every policy here: a probe
  that can't run (no ffprobe, unreadable file, no presence row) returns
  `:skipped` rather than failing, because `probe_missing/0` will pick it
  up on a later sweep. Nothing in the system gates on these values; they
  exist for legibility in the More-info pane.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{FileMediaInfo, FilePresence, Files, Helpers, MediaProbe}
  alias MediaCentaur.Repo

  @doc """
  Probes `file_path` and upserts its `FileMediaInfo` row.

  `:skipped` when probing is unavailable or fails, or the file has no
  presence row — a later sweep can always retry.
  """
  @spec refresh(Ecto.UUID.t() | nil, String.t()) :: :ok | :skipped
  def refresh(nil, _file_path), do: :skipped

  def refresh(file_presence_id, file_path) do
    case MediaProbe.probe(file_path) do
      {:ok, attrs} ->
        attrs = Map.put(attrs, :file_presence_id, file_presence_id)

        case Repo.get_by(FileMediaInfo, file_presence_id: file_presence_id) do
          nil -> Repo.insert!(FileMediaInfo.changeset(%FileMediaInfo{}, attrs))
          existing -> Repo.update!(FileMediaInfo.changeset(existing, attrs))
        end

        :ok

      :error ->
        :skipped
    end
  end

  @doc "Media-info rows keyed by file path — batch read for view builders."
  @spec by_paths([String.t()]) :: %{String.t() => FileMediaInfo.t()}
  def by_paths([]), do: %{}

  def by_paths(paths) when is_list(paths) do
    from(f in FilePresence,
      join: m in FileMediaInfo,
      on: m.file_presence_id == f.id,
      where: f.file_path in ^paths,
      select: {f.file_path, m}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Backfill sweep: probes every file presence with no media-info row yet —
  files imported before this feature, or whose probe failed. Idempotent
  and network-free; run from the boot heal
  (`MediaCentaur.BootHeal.probe_media_info/1`).

  A sweep that filled anything broadcasts `entities_changed` once. The
  boot sweep finishes *after* the detail projection's boot build, so
  without the nudge the More-info pane would render from a cache
  snapshotted while the table was still empty.
  """
  @spec probe_missing() :: %{probed: non_neg_integer(), skipped: non_neg_integer()}
  def probe_missing do
    {summary, probed_presence_ids} =
      from(f in FilePresence,
        left_join: m in FileMediaInfo,
        on: m.file_presence_id == f.id,
        where: is_nil(m.id),
        select: {f.id, f.file_path}
      )
      |> Repo.all()
      |> Enum.reduce({%{probed: 0, skipped: 0}, []}, fn {presence_id, path}, {acc, ids} ->
        case refresh(presence_id, path) do
          :ok -> {%{acc | probed: acc.probed + 1}, [presence_id | ids]}
          :skipped -> {%{acc | skipped: acc.skipped + 1}, ids}
        end
      end)

    if summary.probed > 0 do
      probed_presence_ids
      |> Files.top_level_entity_ids_for_presences()
      |> Helpers.broadcast_entities_changed()
    end

    summary
  end
end
