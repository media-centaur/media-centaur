defmodule MediaCentaur.Subtitles do
  use Boundary, deps: [], exports: [Track]

  @moduledoc """
  Public API for subtitle detection, persistence, and aggregation.

  Responsibilities:

    * `detect/1` runs every available detector against a video file
      path and returns a deduped list of `Track` values. Used at
      pipeline-import time and from the maintenance backfill.
    * `create_track/1`, `list_tracks_for_file/1`, and
      `replace_tracks_for_file/2` are the persistence API — every
      caller goes through here rather than `Repo` directly.
    * `aggregate_languages_for_files/1` is the read-side helper for
      the UI. Given a list of `WatchedFile` ids (or structs), it
      returns a deduped, sorted list of language codes (with a single
      trailing `nil` if any unknown-language sidecar exists). The UI
      treats `nil` as "external".

  Detectors live under `MediaCentaur.Subtitles.Detector.*`. Each is a
  pluggable source (today: ffprobe + sidecar). Adding a new source is
  a single insertion below — every consumer keeps the public API.

  Tracks are persisted in the `subtitles_tracks` table, linked to
  `Library.WatchedFile` via `watched_file_id`. This context owns the
  table; Library reaches the data through these functions.

  This context is its own boundary with no domain dependencies, so it
  can be invoked from anywhere safely.
  """

  import Ecto.Query

  alias MediaCentaur.Repo
  alias MediaCentaur.Subtitles.Detector
  alias MediaCentaur.Subtitles.Track

  # Order matters only for debugging clarity — `detect/1` dedupes, so
  # the result is the union regardless.
  @detectors [Detector.Ffprobe, Detector.Sidecar]

  @doc """
  Runs every detector against `file_path` and returns the deduped
  union of detected tracks.

  Pure with respect to the database — does not persist. Use
  `replace_tracks_for_file/2` to store the result against a
  `WatchedFile`.
  """
  @spec detect(String.t()) :: [Track.t()]
  def detect(file_path) when is_binary(file_path) do
    @detectors
    |> Enum.flat_map(&run_detector(&1, file_path))
    |> Enum.uniq_by(&{&1.kind, &1.source})
  end

  @doc """
  Inserts a single subtitle track.

  `attrs` must include `:watched_file_id`, `:kind`, and `:source`;
  `:language` is optional. See `Track.create_changeset/1` for the
  full contract.
  """
  @spec create_track(map()) :: {:ok, Track.t()} | {:error, Ecto.Changeset.t()}
  def create_track(attrs) when is_map(attrs) do
    attrs
    |> Track.create_changeset()
    |> Repo.insert()
  end

  @doc """
  Returns every persisted track for the given `WatchedFile`, ordered
  by insertion time.
  """
  @spec list_tracks_for_file(Ecto.UUID.t()) :: [Track.t()]
  def list_tracks_for_file(watched_file_id) when is_binary(watched_file_id) do
    Repo.all(
      from t in Track,
        where: t.watched_file_id == ^watched_file_id,
        order_by: [asc: t.inserted_at, asc: t.id]
    )
  end

  @doc """
  Batch variant of `list_tracks_for_file/1`. Given a list of
  `WatchedFile` ids, returns a map of `watched_file_id => [Track.t()]`
  in one query — the read-side projection builders use this to avoid a
  per-file query when assembling tracks for many files at once.

  Files with no tracks are omitted from the map; callers use
  `Map.get(map, id, [])`. An empty id list returns `%{}` without
  touching the database.
  """
  @spec list_tracks_for_files([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => [Track.t()]}
  def list_tracks_for_files([]), do: %{}

  def list_tracks_for_files(watched_file_ids) when is_list(watched_file_ids) do
    Enum.group_by(
      Repo.all(
        from t in Track,
          where: t.watched_file_id in ^watched_file_ids,
          order_by: [asc: t.inserted_at, asc: t.id]
      ),
      & &1.watched_file_id
    )
  end

  @doc """
  Atomically replaces the persisted tracks for a `WatchedFile`.

  Deletes the existing rows and inserts the supplied attrs (or
  `%Track{}` structs from `detect/1`) in a single transaction. The
  `:watched_file_id` field is forced to match the file id parameter,
  so detector output (which carries no FK) can be passed straight
  through.

  Returns `{:ok, [Track.t()]}` on success, `{:error, reason}` if any
  insert fails.
  """
  @spec replace_tracks_for_file(Ecto.UUID.t(), [map() | Track.t()]) ::
          {:ok, [Track.t()]} | {:error, term()}
  def replace_tracks_for_file(watched_file_id, tracks)
      when is_binary(watched_file_id) and is_list(tracks) do
    Repo.transaction(fn ->
      Repo.delete_all(from t in Track, where: t.watched_file_id == ^watched_file_id)

      Enum.map(tracks, fn track ->
        attrs =
          track
          |> to_attrs()
          |> Map.put(:watched_file_id, watched_file_id)

        case create_track(attrs) do
          {:ok, persisted} -> persisted
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Returns a deduped, sorted list of language codes detected across
  every supplied file.

  Accepts either `WatchedFile` ids (binary UUIDs) or structs/maps
  that expose `:id`. Issues a single DB query. Known languages are
  sorted alphabetically; if any unknown-language sidecar exists,
  a single trailing `nil` is appended.
  """
  @spec aggregate_languages_for_files([Ecto.UUID.t() | %{id: Ecto.UUID.t()}]) ::
          [String.t() | nil]
  def aggregate_languages_for_files(files) when is_list(files) do
    ids = Enum.map(files, &resolve_id/1)

    case ids do
      [] ->
        []

      ids ->
        from(t in Track, where: t.watched_file_id in ^ids, select: t.language)
        |> Repo.all()
        |> sort_with_nil_last()
    end
  end

  @doc """
  Same display aggregation as `aggregate_languages_for_files/1`, but over
  already-loaded track structs/maps (anything exposing `:language`) —
  no query. For callers holding the detail projection's
  `DetailItem.SubtitleTrack`s, which carry the same tracks the file
  query would return.
  """
  @spec aggregate_track_languages([%{:language => String.t() | nil, optional(atom()) => term()}]) ::
          [String.t() | nil]
  def aggregate_track_languages(tracks) when is_list(tracks) do
    tracks |> Enum.map(& &1.language) |> sort_with_nil_last()
  end

  defp resolve_id(%{id: id}) when is_binary(id), do: id
  defp resolve_id(id) when is_binary(id), do: id

  defp run_detector(Detector.Ffprobe, file_path), do: Detector.Ffprobe.probe(file_path)
  defp run_detector(Detector.Sidecar, file_path), do: Detector.Sidecar.scan(file_path)

  defp to_attrs(%Track{} = track) do
    %{kind: track.kind, language: track.language, source: track.source}
  end

  defp to_attrs(attrs) when is_map(attrs), do: attrs

  defp sort_with_nil_last(languages) do
    {known, unknown} = Enum.split_with(languages, &is_binary/1)

    sorted_known = known |> Enum.uniq() |> Enum.sort()

    if unknown == [], do: sorted_known, else: sorted_known ++ [nil]
  end
end
