defmodule MediaCentaur.Review do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.TMDB],
    exports: [
      EpisodeChoice,
      PendingFile,
      Rematch,
      Search,
      # Subscribers to `review:updates` pattern-match these payloads, so
      # they are part of the context's published surface (ADR-060). Same
      # precedent as `Library.Events` / `Events.EntitiesChanged`.
      Events,
      Events.FileAdded,
      Events.FileReviewed,
      Events.FilesApproved
    ]

  @moduledoc """
  The review domain — files requiring human review before library ingestion.

  Provides the `PendingFile` resource for tracking low-confidence matches.
  The ReviewLive UI reads PendingFile records for display and uses these
  functions for approve, dismiss, search, and match-selection workflows.

  Approval broadcasts a `{:file_matched, ...}` event to `MediaCentaur.Topics.pipeline_matched()`,
  which the Import Pipeline Producer picks up for async processing via Broadway.

  ## An item closes on its file's link outcome

  An approved item stays in the queue until the library reports what
  became of its file (`Library.Inbound`, "Link outcome", on
  `Topics.library_file_events/0`; `Review.FileEventHandler` routes it):

    * linked or parked → `file_linked/1` / `file_parked/1` remove the item;
    * not linked → `file_not_linked/1` returns it to `:pending` with the
      reason in `error_message`, keeping the reviewer's match, or queues
      the file if it had no item (an automatic match that linked nothing).

  Nothing else closes an approved item, so an approval can no longer end
  with the item gone and the title absent. `settle_with_library/0`
  settles at startup whatever a dropped message left behind.
  """
  import Ecto.Query

  alias MediaCentaur.Repo
  alias MediaCentaur.Library
  alias MediaCentaur.TMDB
  alias MediaCentaur.Library.Deletion
  alias MediaCentaur.Review.PendingFile

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Parser
  alias MediaCentaur.Review.Events
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.Events.FilesApproved
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

  @doc """
  The open review for `attrs`' path, creating one if there is none.

  `file_path` is unique, so there is at most one row per path and its
  status says what state that path's review is in:

    * `:pending` — an open review; returned unchanged, which is what
      makes repeated detection idempotent.
    * `:approved` **and the file is linked** — the import finished, so
      `file_linked/1` should have destroyed this row and a dropped
      `{:file_linked, path}` message left it behind. Stale: reopened,
      because otherwise the row exists but the queue does not list it and
      the path can never be reviewed again.
    * `:approved` **and the file is not linked** — the decision is made
      and the import is still outstanding. Returned unchanged; reopening
      would put a file back in the queue while it is being imported.
    * `:dismissed` — a person decided the path is not library content.
      Returned unchanged, so it keeps blocking. `reopen_for_review/1` is
      the deliberate override.
  """
  def find_or_create_pending_file(attrs) do
    file_path = attrs[:file_path] || attrs["file_path"]

    case Repo.get_by(PendingFile, file_path: file_path) do
      nil -> Repo.insert(PendingFile.create_changeset(attrs))
      %PendingFile{status: :approved} = existing -> maybe_reopen_completed(existing, attrs)
      existing -> {:ok, existing}
    end
  end

  defp maybe_reopen_completed(%PendingFile{file_path: file_path} = existing, attrs) do
    if Library.Files.linked?(file_path) do
      Repo.update(PendingFile.reopen_changeset(existing, attrs))
    else
      {:ok, existing}
    end
  end

  @doc """
  Puts a path back in the queue whatever was decided about it before,
  and broadcasts `FileAdded`.

  The re-match path (`Library.Inbound` handing an entity's files back).
  Unlike detection it is an explicit act on files the user owns, so it
  supersedes an older decision — a dismissal included, which every
  automatic path still refuses to reconsider. It is also, for now, the
  only way to undo a dismissal: nothing in the UI lists dismissed files.
  """
  @spec reopen_for_review(map()) :: {:ok, PendingFile.t()} | {:error, term()}
  def reopen_for_review(attrs) do
    file_path = attrs[:file_path] || attrs["file_path"]

    result =
      case Repo.get_by(PendingFile, file_path: file_path) do
        nil -> Repo.insert(PendingFile.create_changeset(attrs))
        existing -> Repo.update(PendingFile.reopen_changeset(existing, attrs))
      end

    with {:ok, pending_file} <- result do
      Events.broadcast(%FileAdded{pending_file_id: pending_file.id})
      {:ok, pending_file}
    end
  end

  @doc """
  Settles the queue against the library at startup, when nothing is in
  flight: an item whose file is linked is done and removed, and an
  `:approved` item whose file is not linked is an import that did not
  finish — it returns to `:pending` with that reason.

  The link outcomes that close and reopen items (`file_linked/1`,
  `file_not_linked/1`) travel over PubSub, which has no replay; a listener
  not subscribed at that instant loses one. A live instance once carried
  73 approved rows orphaned that way, invisible in the queue. `:dismissed`
  rows are decisions and are left alone. Returns the counts.
  """
  @spec settle_with_library() :: %{closed: non_neg_integer(), reopened: non_neg_integer()}
  def settle_with_library do
    open =
      PendingFile
      |> where([p], p.status in [:pending, :approved])
      |> select([p], %{id: p.id, file_path: p.file_path, status: p.status})
      |> Repo.all()

    linked = Library.Files.linked_paths(Enum.map(open, & &1.file_path))
    {done, unlinked} = Enum.split_with(open, &MapSet.member?(linked, &1.file_path))
    unfinished_ids = for %{status: :approved, id: id} <- unlinked, do: id

    done_ids = Enum.map(done, & &1.id)
    {closed, _} = Repo.delete_all(from(p in PendingFile, where: p.id in ^done_ids))

    {reopened, _} =
      Repo.update_all(from(p in PendingFile, where: p.id in ^unfinished_ids),
        set: [
          status: :pending,
          error_message: unlinked_message(:unfinished),
          updated_at: DateTime.utc_now(:second)
        ]
      )

    Enum.each(done_ids, &broadcast_reviewed/1)
    Enum.each(unfinished_ids, &Events.broadcast(%FileAdded{pending_file_id: &1}))

    if closed + reopened > 0 do
      Log.info(
        :review,
        "startup recovery — closed #{closed} review item(s) whose file is linked, " <>
          "reopened #{reopened} whose import did not finish"
      )
    end

    %{closed: closed, reopened: reopened}
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
        case reopen_for_review(parsed_pending_attrs(file)) do
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
  True when `file_path` was dismissed in review — a person decided it
  is not library content.

  Terminal, the same way being linked is. `find_or_create_pending_file/1`
  keys on `file_path` regardless of status, so a dismissed row can never
  be replaced by a fresh pending one: any match computed for that path
  afterwards is discarded. `Pipeline.Discovery` reads this to stop before
  the parse and the two TMDB searches whose result it could not use.

  A `:pending` row is deliberately *not* terminal — it is an open
  question, and `Watcher.Rescan.rescan_unlinked/0` exists to re-run those
  once a transient failure (a rejected TMDB key) is resolved.
  """
  @spec dismissed?(String.t()) :: boolean()
  def dismissed?(file_path) when is_binary(file_path) do
    Repo.exists?(
      from(p in PendingFile, where: p.file_path == ^file_path and p.status == :dismissed, limit: 1)
    )
  end

  @doc """
  Drops the queue rows for `file_paths` — the files are no longer
  library content, so there is no decision left to make about them.

  Status-blind on purpose: a `:dismissed` row is queue state too, and
  `find_or_create_pending_file/1` keys on `file_path` regardless of
  status, so leaving one behind would keep the path permanently
  un-queueable if it ever came back.

  Called by `Review.FileEventHandler` for both producers of
  `{:files_removed, paths}` — a deletion observed on disk, and an
  ignore rule retracting a path. Returns `{:ok, count}`.
  """
  @spec drop_pending_files([String.t()]) :: {:ok, non_neg_integer()}
  def drop_pending_files([]), do: {:ok, 0}

  def drop_pending_files(file_paths) when is_list(file_paths) do
    dropped_ids =
      PendingFile
      |> where([p], p.file_path in ^file_paths)
      |> select([p], p.id)
      |> Repo.all()

    {count, _} = Repo.delete_all(from(p in PendingFile, where: p.id in ^dropped_ids))
    Enum.each(dropped_ids, &broadcast_reviewed/1)

    {:ok, count}
  end

  @doc """
  The library linked `file_path`: its review, if any, is answered.
  Removes the item and broadcasts `FileReviewed`. A dismissed item is a
  decision and stays.
  """
  @spec file_linked(String.t()) :: :ok
  def file_linked(file_path), do: close_review(file_path)

  @doc """
  The pipeline parked `file_path` in the episode-mapping queue, which owns
  it from here: its review item is removed, as for `file_linked/1`.
  """
  @spec file_parked(String.t()) :: :ok
  def file_parked(file_path), do: close_review(file_path)

  defp close_review(file_path) do
    with %PendingFile{status: status} = pending_file when status in [:pending, :approved] <-
           Repo.get_by(PendingFile, file_path: file_path),
         {:ok, _} <- destroy_pending_file(pending_file) do
      Log.info(:review, "\"#{Path.basename(file_path)}\" is in the library — review closed")
      broadcast_reviewed(pending_file.id)
    end

    :ok
  end

  @doc """
  The library did not link the file: `%{file_path, media_dir, reason,
  match}`, as `Library.Inbound` and `Pipeline.Import` report it — `match`
  is the `%{tmdb_id, tmdb_type}` the file was imported under, or nil.

  An `:approved` or `:pending` item returns to `:pending` with the reason
  in `error_message`, keeping the match the reviewer chose. A file with no
  item is queued with the reason and the match it was imported under — an
  automatic match that linked nothing needs a person too, and approving it
  again is the retry. A dismissed item stays dismissed. Broadcasts
  `FileAdded`.
  """
  @spec file_not_linked(%{
          file_path: String.t(),
          media_dir: String.t(),
          reason: term(),
          match: %{tmdb_id: integer(), tmdb_type: :movie | :tv} | nil
        }) :: :ok
  def file_not_linked(%{file_path: file_path, media_dir: media_dir, reason: reason, match: match}) do
    message = unlinked_message(reason)

    result =
      case Repo.get_by(PendingFile, file_path: file_path) do
        nil ->
          %{file_path: file_path, media_dir: media_dir}
          |> parsed_pending_attrs()
          |> Map.merge(match_attrs(match))
          |> Map.put(:error_message, message)
          |> PendingFile.create_changeset()
          |> Repo.insert()

        %PendingFile{status: :dismissed} ->
          :dismissed

        pending_file ->
          Repo.update(PendingFile.unlinked_changeset(pending_file, message))
      end

    case result do
      {:ok, pending_file} ->
        Log.info(:review, "\"#{Path.basename(file_path)}\" was not added — back in review: #{message}")
        Events.broadcast(%FileAdded{pending_file_id: pending_file.id})

      :dismissed ->
        :ok

      {:error, changeset} ->
        Log.warning(:review, "failed to reopen #{file_path} — #{inspect(changeset.errors)}")
    end

    :ok
  end

  defp match_attrs(nil), do: %{}

  defp match_attrs(%{tmdb_id: tmdb_id, tmdb_type: tmdb_type}),
    do: %{tmdb_id: tmdb_id, tmdb_type: to_string(tmdb_type)}

  # What the reviewer reads on a returned item: what happened, and the one
  # thing to do about it.
  defp unlinked_message(:no_episode),
    do:
      "This file has no season and episode number, so it can't be added to a series " <>
        "until you choose its episode. Match it to the series and choose the episode, " <>
        "or match it to a movie."

  defp unlinked_message({:ingest_failed, _reason}),
    do: "Adding it to the library failed. Approve it again to retry."

  defp unlinked_message(:crashed), do: "Adding it to the library failed. Approve it again to retry."

  defp unlinked_message({:import_failed, :insufficient_disk_space}),
    do: "There isn't enough disk space to import it. Free some space and approve it again."

  defp unlinked_message({:import_failed, _reason}), do: "Importing it failed. Approve it again to retry."

  defp unlinked_message(:unfinished),
    do: "Importing it didn't finish before the app stopped. Approve it again to retry."

  # Parses the same path discovery and import parse, so it reads the same
  # extras setting. It used to fall through to `Parser`'s own literal
  # list, which no user can change: a folder name the user added was
  # ignored here, and one the user removed still classified as a bonus
  # feature.
  defp parsed_pending_attrs(file) do
    file.file_path
    |> Parser.parse(extras_dirs: MediaCentaur.Settings.Config.extras_dirs())
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
  # Choosing the episode
  # ---------------------------------------------------------------------------

  @doc """
  True when `pending_file` is matched to a series but carries no season and
  episode, so the library would have nothing to attach it to. The reviewer
  chooses the episode (`set_episode/3`) before it can be approved. A bonus
  feature belongs to the series itself and needs none.
  """
  @spec needs_episode?(PendingFile.t()) :: boolean()
  def needs_episode?(%PendingFile{} = pending_file), do: PendingFile.needs_episode?(pending_file)

  @doc """
  True when `pending_file` is matched to a series and its name does not
  number the episode, so the reviewer chooses it — and can change the
  choice once made, which is why this reads the name rather than the
  stored season and episode.
  """
  @spec chooses_episode?(PendingFile.t()) :: boolean()
  def chooses_episode?(%PendingFile{tmdb_type: "tv", parsed_type: parsed_type, file_path: file_path})
      when parsed_type != "extra" do
    is_nil(Parser.parse(file_path, extras_dirs: MediaCentaur.Settings.Config.extras_dirs()).episode)
  end

  def chooses_episode?(%PendingFile{}), do: false

  @doc "Places `pending_file` at the reviewer's chosen season and episode."
  @spec set_episode(PendingFile.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, PendingFile.t()} | {:error, Ecto.Changeset.t()}
  def set_episode(%PendingFile{} = pending_file, season_number, episode_number) do
    Repo.update(PendingFile.set_episode_changeset(pending_file, season_number, episode_number))
  end

  @doc """
  The seasons of TMDB series `tmdb_id` with their episodes, for the
  reviewer's episode picker: `[%{season_number, name, episodes:
  [%{episode_number, name, air_date}]}]`, regular seasons in order and
  specials (season 0) last. Read through `TMDB.Store`, so a series the app
  already holds costs no request.
  """
  @spec episode_choices(integer()) :: {:ok, [map()]} | {:error, term()}
  def episode_choices(tmdb_id) do
    with {:ok, %TMDB.Store.TitleRecord{payload: payload}} <- TMDB.Store.ensure({tmdb_id, :tv_series}) do
      payload
      |> Map.get("seasons", [])
      |> Enum.sort_by(&{&1["season_number"] == 0, &1["season_number"]})
      |> Enum.reduce_while({:ok, []}, fn season, {:ok, acc} ->
        case TMDB.Store.ensure_season(tmdb_id, season["season_number"]) do
          {:ok, %TMDB.Store.SeasonRecord{payload: season_payload}} ->
            choice = %{
              season_number: season["season_number"],
              name: season["name"],
              episodes: TMDB.Mapper.episode_list(season_payload)
            }

            {:cont, {:ok, [choice | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> then(fn
        {:ok, seasons} -> {:ok, Enum.reverse(seasons)}
        error -> error
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Business logic
  # ---------------------------------------------------------------------------

  @doc """
  The review page's groups: every open item — `:pending`, awaiting a
  decision, and `:approved`, awaiting its file's link outcome — grouped by
  series root, the first directory component below the media directory.
  Two files share a group when they have the same
  `{media_directory, series_root}`.

  Returns a list of group maps:

      %{key: {media_dir, root}, files: [pending_files], representative: file}

  Single-file groups (movies, flat downloads) are groups of 1 — same shape.
  The representative is `representative/1` of the files.
  """
  def fetch_review_groups do
    Repo.all(
      from(p in PendingFile,
        where: p.status in [:pending, :approved],
        order_by: [asc: p.inserted_at]
      )
    )
    |> Enum.group_by(fn file ->
      {file.media_directory, series_root(file)}
    end)
    |> Enum.map(fn {key, files} ->
      %{key: key, files: files, representative: representative(files)}
    end)
  end

  @doc """
  The file a group is shown and judged by: its first file still awaiting
  a decision, or its first file when every one is importing. A file that
  joins a group whose other files are importing is what the reviewer acts
  on, not hidden behind them.
  """
  @spec representative([PendingFile.t(), ...]) :: PendingFile.t()
  def representative([first | _] = files), do: Enum.find(files, first, &(&1.status == :pending))

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
  Approves a group as one decision: its files still `:pending`, read fresh
  by `file_ids`, are approved and each match is sent to Import. Files
  already approved or dismissed are left alone.

  The group is refused whole when its pending files do not share one
  identity (`group_identity/1`) — a file without one would reach Import
  with no type, and files with different ones are not the single match the
  reviewer saw. Returns `{:ok, approved_count}` and broadcasts
  `FilesApproved`, or `{:error, :no_identity | :mixed_identities}`.
  """
  @spec approve_group([Ecto.UUID.t()]) ::
          {:ok, non_neg_integer()} | {:error, :no_identity | :mixed_identities}
  def approve_group(file_ids) when is_list(file_ids) do
    pending = Repo.all(from(p in PendingFile, where: p.id in ^file_ids and p.status == :pending))

    with {:ok, _identity} <- group_identity(pending) do
      approved_ids =
        for file <- pending, match?({:ok, _}, approve_and_process(file)), do: file.id

      if approved_ids != [], do: Events.broadcast(%FilesApproved{pending_file_ids: approved_ids})
      {:ok, length(approved_ids)}
    end
  end

  @doc """
  The identity — `{tmdb_id, tmdb_type}` — every file in `files` shares, or
  why there is none: `:no_identity` when a file has no match (reported
  first, since choosing a match fixes both), `:mixed_identities` when the
  files carry different ones. An empty list has no identity.
  """
  @spec group_identity([PendingFile.t()]) ::
          {:ok, {integer(), String.t()}} | {:error, :no_identity | :mixed_identities}
  def group_identity(files) do
    identities = files |> Enum.map(&{&1.tmdb_id, &1.tmdb_type}) |> Enum.uniq()

    cond do
      identities == [] -> {:error, :no_identity}
      Enum.any?(identities, fn {id, type} -> is_nil(id) or is_nil(type) end) -> {:error, :no_identity}
      match?([_], identities) -> {:ok, hd(identities)}
      true -> {:error, :mixed_identities}
    end
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
           season: pending_file.season_number,
           episode: pending_file.episode_number
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

    # An episode the reviewer chose belongs to the series it was chosen from.
    chosen_episode =
      if chooses_episode?(pending_file), do: %{season_number: nil, episode_number: nil}, else: %{}

    set_pending_file_match(
      pending_file,
      Map.merge(chosen_episode, %{
        tmdb_id: tmdb_id_int,
        tmdb_type: tmdb_type,
        match_title: title,
        match_year: year,
        match_poster_path: poster_path,
        confidence: 1.0
      })
    )
  end

  defp broadcast_reviewed(file_id) do
    Events.broadcast(%FileReviewed{pending_file_id: file_id})
  end
end
