defmodule MediaCentaur.Review do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.TMDB],
    exports: [
      PendingFile,
      Rematch,
      Search,
      # Subscribers to `review:updates` pattern-match these payloads, so
      # they are part of the context's published surface (ADR-060). Same
      # precedent as `Library.Events` / `Events.EntitiesChanged`.
      Events,
      Events.FileAdded,
      Events.FileReviewed,
      Events.GroupApproved,
      Events.GroupError
    ]

  @moduledoc """
  The review domain — files requiring human review before library ingestion.

  Provides the `PendingFile` resource for tracking low-confidence matches.
  The ReviewLive UI reads PendingFile records for display and uses these
  functions for approve, dismiss, search, and match-selection workflows.

  Approval broadcasts a `{:file_matched, ...}` event to `MediaCentaur.Topics.pipeline_matched()`,
  which the Import Pipeline Producer picks up for async processing via Broadway.
  """
  import Ecto.Query

  alias MediaCentaur.Repo
  alias MediaCentaur.Library.Deletion
  alias MediaCentaur.Review.PendingFile

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Parser
  alias MediaCentaur.Review.Events
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.GroupApproved
  alias MediaCentaur.Review.Events.GroupError
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to review process events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.review_updates())
  end

  # ---------------------------------------------------------------------------
  # PendingFile CRUD
  # ---------------------------------------------------------------------------

  def list_pending_files, do: Repo.all(PendingFile)

  @doc """
  Destroys every `PendingFile` row, whatever its status. The Review half
  of `MediaCentaur.Maintenance.clear_database/0`; nothing on disk is
  touched.
  """
  @spec clear_all() :: :ok
  def clear_all do
    Repo.delete_all(PendingFile)
    :ok
  end

  def fetch_pending_file(id) do
    case Repo.get(PendingFile, id) do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  end

  def list_pending_files_for_review do
    Repo.all(
      from(p in PendingFile,
        where: p.status == :pending,
        order_by: [asc: p.inserted_at]
      )
    )
  end

  @doc "Number of files still awaiting review (status `:pending`)."
  @spec count_pending() :: non_neg_integer()
  def count_pending do
    Repo.aggregate(from(p in PendingFile, where: p.status == :pending), :count)
  end

  @doc """
  Returns the set of file paths currently awaiting review (status
  `:pending`). Used by `Acquisition` to resolve whether a pursuit's
  downloaded file is sitting in the review queue, as a batched membership
  test rather than a per-pursuit query.
  """
  @spec pending_file_paths() :: MapSet.t(String.t())
  def pending_file_paths do
    PendingFile
    |> where([p], p.status == :pending)
    |> select([p], p.file_path)
    |> Repo.all()
    |> MapSet.new()
  end

  def create_pending_file(attrs) do
    Repo.insert(PendingFile.create_changeset(attrs))
  end

  def create_pending_file!(attrs), do: Repo.bang!(create_pending_file(attrs))

  def find_or_create_pending_file(attrs) do
    file_path = attrs[:file_path] || attrs["file_path"]

    case Repo.get_by(PendingFile, file_path: file_path) do
      nil -> Repo.insert(PendingFile.create_changeset(attrs))
      existing -> {:ok, existing}
    end
  end

  def find_or_create_pending_file!(attrs), do: Repo.bang!(find_or_create_pending_file(attrs))

  @doc """
  Adds a file to the review queue from pre-normalized attributes and
  broadcasts `FileAdded`. Idempotent on `file_path` — a second call
  returns the existing record.
  """
  @spec add_pending_file(map()) :: {:ok, PendingFile.t()} | {:error, term()}
  def add_pending_file(attrs) do
    with {:ok, pending_file} <- find_or_create_pending_file(attrs) do
      Events.broadcast(%FileAdded{pending_file_id: pending_file.id})
      {:ok, pending_file}
    end
  end

  @doc """
  Adds files handed back by a rematch — each `%{file_path, media_dir}`
  is parsed for its metadata first. Returns `{:ok, count}` of files
  added; one that fails to save is logged and skipped.
  """
  @spec add_files_for_review([map()]) :: {:ok, non_neg_integer()}
  def add_files_for_review(files) do
    added =
      Enum.count(files, fn file ->
        case add_pending_file(parsed_pending_attrs(file)) do
          {:ok, _pending_file} ->
            true

          {:error, reason} ->
            Log.warning(:review, "failed to create pending file for rematch — #{inspect(reason)}")
            false
        end
      end)

    Log.info(:review, "rematch — created #{added} pending files")
    {:ok, added}
  end

  @doc """
  Removes a file from the review queue once its import has finished and
  broadcasts `FileReviewed`. `:ok` even when the record is already gone.
  """
  @spec complete_review(Ecto.UUID.t()) :: :ok
  def complete_review(pending_file_id) do
    case fetch_pending_file(pending_file_id) do
      {:ok, pending_file} ->
        destroy_pending_file!(pending_file)
        broadcast_reviewed(pending_file_id)

      {:error, :not_found} ->
        :ok
    end
  end

  defp parsed_pending_attrs(file) do
    file.file_path
    |> Parser.parse()
    |> PendingFile.parsed_attrs()
    |> Map.merge(%{file_path: file.file_path, media_directory: file.media_dir})
  end

  def approve_pending_file(pending_file) do
    Repo.update(PendingFile.approve_changeset(pending_file))
  end

  def dismiss_pending_file(pending_file) do
    Repo.update(PendingFile.dismiss_changeset(pending_file))
  end

  def set_pending_file_match(pending_file, attrs) do
    Repo.update(PendingFile.set_tmdb_match_changeset(pending_file, attrs))
  end

  def destroy_pending_file(pending_file), do: Repo.delete(pending_file)

  def destroy_pending_file!(pending_file) do
    Repo.bang!(Repo.delete(pending_file))
    :ok
  end

  # ---------------------------------------------------------------------------
  # Business logic
  # ---------------------------------------------------------------------------

  @doc """
  Groups pending files by series root — the first directory component below
  the media directory. Two files share a group when they have the same
  `{media_directory, series_root}`.

  Returns a list of group maps:

      %{key: {media_dir, root}, files: [pending_files], representative: first_file}

  Single-file groups (movies, flat downloads) are groups of 1 — same shape.
  """
  def fetch_pending_groups do
    list_pending_files_for_review()
    |> Enum.group_by(fn file ->
      {file.media_directory, series_root(file)}
    end)
    |> Enum.map(fn {key, files} ->
      %{key: key, files: files, representative: hd(files)}
    end)
  end

  @doc """
  Extracts the series root — the first path component below the media directory.

  Examples:

      /media/tv/Sample Show (2001)/Season 1/ep.mkv  ->  "Sample Show (2001)"
      /media/movies/movie.mkv                   ->  "movie.mkv"
  """
  def series_root(%{file_path: file_path, media_directory: nil}), do: file_path

  def series_root(%{file_path: file_path, media_directory: media_dir}) do
    relative = String.replace_prefix(file_path, media_dir <> "/", "")

    case Path.split(relative) do
      [single] -> single
      [root | _] -> root
    end
  end

  @doc """
  Approves all files in a group and sends them to the pipeline.
  Returns `{approved_count, error_count}`.
  """
  def approve_group(files) do
    results = Enum.map(files, &approve_and_process/1)
    approved = Enum.count(results, &match?({:ok, _}, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))
    {approved, errors}
  end

  @doc """
  Fire-and-forget group approval. Runs the (file-moving) `approve_group/1`
  on a supervised context-layer task — the approval must complete
  regardless of the review LiveView's lifecycle (ADR-049: must-outlive
  background work lives in the context, not a web-layer `start_child`).
  Per-group results are broadcast on `Topics.review_updates/0`.
  """
  def approve_group_async(group_key, files) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      {approved, errors} = approve_group(files)

      if errors > 0 do
        Events.broadcast(%GroupError{
          group_key: group_key,
          message: "#{errors} file(s) failed to approve"
        })
      end

      if approved > 0 do
        Events.broadcast(%GroupApproved{group_key: group_key, count: approved})
      end
    end)

    :ok
  end

  @doc """
  Dismisses all files in a group.
  Returns `{dismissed_count, error_count}`.
  """
  def dismiss_group(files) do
    results = Enum.map(files, &dismiss/1)
    dismissed = Enum.count(results, &match?({:ok, _}, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))
    {dismissed, errors}
  end

  @doc """
  Deletes all files in a group individually from disk (and their DB
  records) — for review items the user never wants, e.g. a broken/
  incomplete download. Use this when no shared folder was deemed safe
  to delete wholesale (see `MediaCentaur.DeleteTargets`); when one was,
  the caller deletes the folder itself and calls
  `destroy_pending_files/1` instead.
  Returns `{deleted_count, error_count}`.
  """
  def delete_group(files) do
    results = Enum.map(files, &delete_pending_file/1)
    deleted = Enum.count(results, &match?({:ok, _}, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))
    {deleted, errors}
  end

  @doc """
  Destroys the `PendingFile` records for `files` without touching disk —
  for when the caller has already deleted the containing folder directly
  (via `MediaCentaur.Library.Deletion.delete_folder/2`, guarded
  by `MediaCentaur.DeleteTargets.resolve_folder_target/1`). This only
  cleans up the DB record Review alone owns; `Deletion` has no
  concept of a `PendingFile`.
  """
  @spec destroy_pending_files([PendingFile.t()]) :: :ok
  def destroy_pending_files(files) do
    Enum.each(files, fn file ->
      destroy_pending_file(file)
      Log.info(:review, "deleted \"#{Path.basename(file.file_path)}\" — removed from review")
      broadcast_reviewed(file.id)
    end)

    :ok
  end

  @doc """
  Sets the TMDB match on all files in a group.
  Returns `{updated_count, error_count}`.
  """
  def set_group_match(files, match) do
    results = Enum.map(files, &set_tmdb_match(&1, match))
    updated = Enum.count(results, &match?({:ok, _}, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))
    {updated, errors}
  end

  defp approve_and_process(pending_file) do
    Log.info(
      :review,
      "approved \"#{Path.basename(pending_file.file_path)}\" — tmdb:#{pending_file.tmdb_id} (#{pending_file.tmdb_type})"
    )

    with {:ok, pending_file} <- approve_pending_file(pending_file) do
      Topics.publish(
        MediaCentaur.Topics.pipeline_matched(),
        {:file_matched,
         %{
           file_path: pending_file.file_path,
           media_dir: pending_file.media_directory,
           tmdb_id: pending_file.tmdb_id,
           tmdb_type: pending_file.tmdb_type,
           pending_file_id: pending_file.id
         }}
      )

      {:ok, pending_file}
    end
  end

  def dismiss(pending_file) do
    result = dismiss_pending_file(pending_file)

    if match?({:ok, _}, result) do
      Log.info(:review, "dismissed \"#{Path.basename(pending_file.file_path)}\"")
      broadcast_reviewed(pending_file.id)
    end

    result
  end

  @doc """
  Deletes the underlying file from disk (and its `Library.FilePresence`
  row, via `Deletion.delete_file/1` — the same primitive the
  entity detail page uses), then destroys the `PendingFile` record
  entirely. Unlike `dismiss/1` (which only flips `status: :dismissed`
  and leaves everything else in place), this removes the clutter for a
  review item the user never wants imported.
  """
  @spec delete_pending_file(PendingFile.t()) :: {:ok, PendingFile.t()} | {:error, term()}
  def delete_pending_file(pending_file) do
    case Deletion.delete_file(pending_file.file_path) do
      {:ok, _entity_ids} ->
        result = destroy_pending_file(pending_file)

        if match?({:ok, _}, result) do
          Log.info(
            :review,
            "deleted \"#{Path.basename(pending_file.file_path)}\" — removed from review"
          )

          broadcast_reviewed(pending_file.id)
        end

        result

      {:error, reason} ->
        Log.warning(
          :review,
          "failed to delete #{pending_file.file_path}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp set_tmdb_match(pending_file, %{
         tmdb_id: tmdb_id,
         tmdb_type: tmdb_type,
         title: title,
         year: year,
         poster_path: poster_path
       }) do
    tmdb_id_int =
      case tmdb_id do
        id when is_integer(id) -> id
        id when is_binary(id) -> String.to_integer(id)
      end

    set_pending_file_match(pending_file, %{
      tmdb_id: tmdb_id_int,
      tmdb_type: tmdb_type,
      match_title: title,
      match_year: year,
      match_poster_path: poster_path,
      confidence: 1.0
    })
  end

  defp broadcast_reviewed(file_id) do
    Events.broadcast(%FileReviewed{pending_file_id: file_id})
  end
end
