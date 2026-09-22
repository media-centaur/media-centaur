defmodule MediaCentaurWeb.Live.TitleDetailHost.LibraryHalf do
  @moduledoc """
  The library half of a title detail, for the host: loading it by
  identity, reloading it in place, merging the playback broadcasts into
  it without a read, and the deferred file-info load.

  `load/1` resolves the owner the library has for a TMDB ref
  (`Library.ExternalIds.tmdb_owners/1`) to its presentable container
  (`Library.Presentable.resolve/1`) and composes it by kind — a
  `SeriesDetail`, a `CollectionDetail` or a `LeafDetail` — into a
  `Title.Detail.Library`; a collection speaks of the member the ref
  names. `load_entity/1` does the same from an entity id — the residue's
  address, and what an entity emitter hands the host — selecting the
  member the id names. Both are projection reads, milliseconds
  (ADR-051), synchronous on open like every local fact. Nil when the
  library does not own the title, or owns it without a present file.

  The playback broadcasts carry what changed, so `merge_progress/2`,
  `merge_extra_progress/2` and `put_track_override/2` update the half
  in memory (`SeriesDetail.with_progress/4` and its collection twin
  keep their typed lists) rather than re-reading on every tick.

  The file-info load stats every file (a stale network mount can take
  seconds to fail `File.stat/1`), so it runs as an owned async
  (ADR-049) under the host and lands by subject.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, start_async: 3]

  alias MediaCentaur.Library
  alias MediaCentaur.Library.EntityView
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Library.Presentable
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Detail.Library, as: Half
  alias MediaCentaurWeb.LibraryProgress
  alias MediaCentaurWeb.TitleRef
  alias MediaCentaurWeb.ViewModel.CollectionDetail
  alias MediaCentaurWeb.ViewModel.LeafDetail
  alias MediaCentaurWeb.ViewModel.MovieRow
  alias MediaCentaurWeb.ViewModel.SeriesDetail

  require MediaCentaur.Log, as: Log

  @type subject :: {:title, TitleRef.ref()} | {:entity, Ecto.UUID.t()}

  # --- Loading ---

  @spec load(TitleRef.ref()) :: Half.t() | nil
  def load({tmdb_id, _media_type} = ref) do
    with owner_id when is_binary(owner_id) <- Map.get(ExternalIds.tmdb_owners([ref]), ref),
         {kind, id} <- Presentable.resolve(owner_id),
         {:ok, entry} <- compose(kind, id) do
      Half.new(entry, member_id(entry, tmdb_id), available: available?(entry))
    else
      _unowned -> nil
    end
  end

  @doc "The half for an entity id; a member id selects that member of its collection."
  @spec load_entity(Ecto.UUID.t()) :: Half.t() | nil
  def load_entity(id) when is_binary(id) do
    with {kind, resolved_id} <- Presentable.resolve(id),
         {:ok, entry} <- compose(kind, resolved_id) do
      member_id = if id != resolved_id, do: id
      Half.new(entry, member_id, available: available?(entry))
    else
      _not_found -> nil
    end
  end

  @doc """
  The address an entity emitter's id resolves to: the title address
  when the subject has a TMDB identity, the entity address for the
  residue, `:not_found` for an id the library has no present file for.
  """
  @spec address(Ecto.UUID.t()) ::
          {:title, TitleRef.ref(), Half.t()} | {:entity, Ecto.UUID.t(), Half.t()} | :not_found
  def address(id) do
    case load_entity(id) do
      nil -> :not_found
      %Half{subject: subject} = half -> subject_address(subject, id, half)
    end
  end

  defp subject_address(subject, id, half) do
    case EntityView.title_ref(subject) do
      {_tmdb_id, _media_type} = ref -> {:title, ref, half}
      nil -> {:entity, id, half}
    end
  end

  @doc "The same half re-read after a mutation, keeping its member and its files."
  @spec reload(Half.t()) :: Half.t() | nil
  def reload(%Half{entry: %{entity: %{id: container_id}}, member: member, files: files}) do
    member_id = member && member.movie.id

    case load_entity(member_id || container_id) do
      nil -> nil
      half -> %{half | files: files}
    end
  end

  @doc "A freshly loaded half carrying the files the open one already has."
  @spec keep_files(Half.t() | nil, Half.t() | nil) :: Half.t() | nil
  def keep_files(%Half{} = fresh, %Half{files: files}), do: %{fresh | files: files}
  def keep_files(fresh, _open), do: fresh

  defp compose(:tv_series, id), do: SeriesDetail.compose(id)
  defp compose(:movie_series, id), do: CollectionDetail.compose(id)
  defp compose(kind, id), do: LeafDetail.compose(kind, id)

  # The member the ref names, so a collection opened on a member's title
  # address speaks of that member (UIDR-023); nil lets the collection
  # pick its default.
  defp member_id(%CollectionDetail{movies: movies}, tmdb_id) do
    Enum.find_value(movies, fn
      %MovieRow.Library{movie: %{tmdb_id: ^tmdb_id, id: id}} -> id
      _other -> nil
    end)
  end

  defp member_id(_entry, _tmdb_id), do: nil

  # Whether the container's media directory is online — carried by the
  # detail projection and patched in place when a drive mounts or unmounts.
  defp available?(%{entity: entity}), do: Map.get(entity, :available?, true)

  # --- The subject and its container ---

  @doc "The open detail's subject: the ref, or the residue's entity id."
  @spec subject(TitleDetail.t()) :: subject()
  def subject(%TitleDetail{ref: {_tmdb_id, _media_type} = ref}), do: {:title, ref}
  def subject(%TitleDetail{library: %Half{entry: %{entity: %{id: id}}}}), do: {:entity, id}

  @doc "The owning container's id, nil for an unowned title."
  @spec container_id(TitleDetail.t()) :: Ecto.UUID.t() | nil
  def container_id(%TitleDetail{library: %Half{entry: %{entity: %{id: id}}}}), do: id
  def container_id(_detail), do: nil

  # --- In-memory merges from the playback broadcasts ---

  @doc "Merges a progress broadcast into the half; nil asks for a reload (a payload without a summary)."
  @spec merge_progress(Half.t(), map()) :: Half.t() | nil
  def merge_progress(%Half{entry: entry} = half, %{
        summary: summary,
        resume_target: resume_target,
        changed_record: changed_record
      })
      when is_map(summary) do
    records = LibraryProgress.merge_progress_record(entry.progress_records, changed_record)

    entry =
      case entry do
        %SeriesDetail{} ->
          SeriesDetail.with_progress(entry, summary, records, resume_target)

        %CollectionDetail{} ->
          CollectionDetail.with_progress(entry, summary, records, resume_target)

        %LeafDetail{} ->
          %{entry | progress: summary, progress_records: records, resume_target: resume_target}
      end

    rebuild(half, entry)
  end

  def merge_progress(_half, _payload), do: nil

  @doc "Merges an extra's progress broadcast into the half's entity."
  @spec merge_extra_progress(Half.t(), map()) :: Half.t() | nil
  def merge_extra_progress(%Half{entry: %{entity: entity} = entry} = half, %{progress: progress})
      when not is_nil(progress) do
    extra_progress = LibraryProgress.merge_extra_progress(entity.extra_progress || [], progress)
    rebuild(half, %{entry | entity: %{entity | extra_progress: extra_progress}})
  end

  def merge_extra_progress(_half, _payload), do: nil

  @doc "Replaces the container's remembered-tracks override in place."
  @spec put_track_override(Half.t(), term()) :: Half.t()
  def put_track_override(%Half{entry: %{entity: entity} = entry} = half, override),
    do: rebuild(half, %{entry | entity: Map.put(entity, :track_override, override)})

  # The subject and member follow the entry; the files stay.
  defp rebuild(%Half{member: member, files: files, available: available}, entry) do
    %{Half.new(entry, member && member.movie.id, available: available) | files: files}
  end

  # --- The deferred file-info load ---

  @doc """
  Starts the file-info load for the open half as an owned async, keyed
  by subject so a result for a title the person has moved on from is
  dropped.
  """
  @spec start_files_load(Phoenix.LiveView.Socket.t(), subject(), Ecto.UUID.t()) ::
          Phoenix.LiveView.Socket.t()
  def start_files_load(socket, subject, container_id) do
    if connected?(socket),
      do: start_async(socket, {:detail_files, subject}, fn -> load_files(container_id) end),
      else: socket
  end

  @doc false
  # Stats every file in parallel with a short per-file timeout; per-call
  # concurrency is small because the bottleneck is filesystem latency.
  def load_files(container_id) do
    container_id
    |> Library.Files.list_by_entity_id()
    |> Task.async_stream(
      fn file ->
        size =
          case File.stat(file.file_path) do
            {:ok, %{size: size}} -> size
            _ -> nil
          end

        %{file: file, size: size}
      end,
      max_concurrency: 8,
      ordered: true,
      timeout: 1_500,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, entry} -> entry
      {:exit, _reason} -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Lands a file-info result on the open half when its subject is still the open one."
  @spec apply_files(Phoenix.LiveView.Socket.t(), subject(), {:ok, [map()]} | {:exit, term()}) ::
          Phoenix.LiveView.Socket.t()
  def apply_files(socket, subject, result) do
    case socket.assigns.title_detail do
      %TitleDetail{library: %Half{} = half} = detail ->
        if subject(detail) == subject do
          files = files_fact(result, subject)
          assign(socket, :title_detail, %{detail | library: %{half | files: files}})
        else
          socket
        end

      _closed_or_unowned ->
        socket
    end
  end

  defp files_fact({:ok, files}, _subject), do: {:ok, files}

  # The panel must say the load failed rather than render an empty
  # inventory as fact.
  defp files_fact({:exit, reason}, subject) do
    Log.error(:library, "detail files load crashed for #{inspect(subject)} — #{inspect(reason)}")
    :failed
  end
end
