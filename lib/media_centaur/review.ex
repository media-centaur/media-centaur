defmodule MediaCentaur.Review do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.Search, MediaCentaur.TMDB],
    exports: [
      PendingFile,
      RememberedMatch,
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
  The review page is a bulk list (`list_queue/0`): a person ticks any set
  of items and acts on their ids — `match/2` (one title for all of them,
  approved in the same step), `approve/1` (each under its own best guess),
  `dismiss/1`, `restore/1`, `delete_files/1`. Nothing here groups files:
  the selection is the unit of decision.

  A person's answer is remembered for the name the files were read as
  (`RememberedMatch`, `remembered_match/3`), and discovery takes it before
  searching TMDB.

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
  with the item gone and the title absent.

  ## Membership follows the library

  Every read of the queue (`open/1`) leaves out files the library has
  linked, so a dropped `{:file_linked, path}` never leaves a linked file
  listed. Deleting the row on that message is storage cleanup, and
  `settle_with_library/0` does the same at startup; neither is what keeps
  the queue correct.
  """
  import Ecto.Query

  alias MediaCentaur.Repo
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Deletion
  alias MediaCentaur.Review.PendingFile
  alias MediaCentaur.Review.RememberedMatch
  alias MediaCentaur.Search.TitleForm

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

  @doc "Number of files still awaiting review (status `:pending`, not linked)."
  @spec count_pending() :: non_neg_integer()
  def count_pending do
    Repo.aggregate(from(p in open(PendingFile), where: p.status == :pending), :count)
  end

  # The rows whose file the library has not linked — the queue's members
  # (see "Membership follows the library").
  defp open(queryable) do
    from(p in queryable, where: p.file_path not in subquery(Library.Files.linked_paths_subquery()))
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
    |> open()
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
  Puts a path back in the queue whatever was decided about it before,
  and broadcasts `FileAdded`.

  The re-match path (`Library.Inbound` handing an entity's files back).
  Unlike detection it is an explicit act on files the user owns, so it
  supersedes an older decision — a dismissal included, which every
  automatic path still refuses to reconsider. A person undoes a dismissal
  from the page with `restore/1`.
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
  Settles the queue against the library: an item whose file is linked is
  done and removed, and an `:approved` item whose file is not linked is an
  approval whose import did not finish — its file is re-sent to Import
  (`send_to_import/1`) and the item stays approved until its link outcome
  closes it (campaign durable-work, F1). The stored approval is the
  durable record of the decision; this pass is what carries it out when a
  PubSub hop to Import or into the library was lost.

  It runs at startup (Discovery's recovery), when nothing is in flight, and
  every few minutes (`Review.SettleJob`) with `approved_before:` — an
  approval younger than that may still be importing and is left alone.

  The link outcomes that close items (`file_linked/1`, `file_not_linked/1`)
  travel over PubSub, which has no replay; a listener not subscribed at
  that instant loses one. A live instance once carried 73 approved rows
  orphaned that way, invisible in the queue. `:dismissed` rows are
  decisions and are left alone. Returns the counts.
  """
  @spec settle_with_library(keyword()) :: %{closed: non_neg_integer(), resent: non_neg_integer()}
  def settle_with_library(opts \\ []) do
    approved_before = Keyword.get(opts, :approved_before, DateTime.utc_now())

    open =
      PendingFile
      |> where([p], p.status in [:pending, :approved])
      |> Repo.all()

    linked = Library.Files.linked_paths(Enum.map(open, & &1.file_path))
    {done, unlinked} = Enum.split_with(open, &MapSet.member?(linked, &1.file_path))

    unfinished =
      Enum.filter(
        unlinked,
        &(&1.status == :approved and DateTime.before?(&1.updated_at, approved_before))
      )

    done_ids = Enum.map(done, & &1.id)
    {closed, _} = Repo.delete_all(from(p in PendingFile, where: p.id in ^done_ids))

    Enum.each(done_ids, &broadcast_reviewed/1)
    Enum.each(unfinished, &send_to_import/1)

    if closed + length(unfinished) > 0 do
      Log.info(
        :review,
        "settled with the library — closed #{closed} review item(s) whose file is linked, " <>
          "re-sent #{length(unfinished)} approval(s) whose import did not finish"
      )
    end

    %{closed: closed, resent: length(unfinished)}
  end

  @doc """
  Why a pending file is in the queue, from its own fields: `:importing`
  (approved, waiting for the library to link it), `:not_added` (the
  library returned it with an `error_message`), `:no_results` (no best
  guess), `:tied` (two or more candidates share the best score) or
  `:low_confidence` (a best guess below the threshold). A dismissed file
  keeps its reason; its status says it was dismissed.
  """
  @spec reason(map()) :: :importing | :not_added | :no_results | :tied | :low_confidence
  def reason(%{status: :approved}), do: :importing
  def reason(%{error_message: message}) when is_binary(message), do: :not_added
  def reason(%{tmdb_id: nil}), do: :no_results

  def reason(file) do
    case Map.get(file, :candidates) do
      [%{"score" => best} | [_ | _] = rest] ->
        if Enum.all?(rest, &(&1["score"] == best)), do: :tied, else: :low_confidence

      _not_tied ->
        :low_confidence
    end
  end

  @doc """
  Discovery's hand-off: the file at `attrs.file_path` needs a person.
  Broadcasts `FileAdded`.

  `file_path` is unique, so there is one row per path, and what happens
  to an existing one depends on its status:

    * `:pending` — discovery ran again (startup, Settings → rescan), so
      the item takes the fresh parse and best guess; a fixed parser reaches
      the queue this way. A not-added item (one with an `error_message`)
      keeps the match the person chose and the reason it failed, and takes
      only the fresh parse.
    * `:approved` — an import still outstanding; left alone.
    * `:dismissed` — a person's decision, which keeps blocking;
      `reopen_for_review/1` is the deliberate override.
  """
  @spec add_pending_file(map()) :: {:ok, PendingFile.t()} | {:error, term()}
  def add_pending_file(attrs) do
    file_path = attrs[:file_path] || attrs["file_path"]

    result =
      case Repo.get_by(PendingFile, file_path: file_path) do
        nil ->
          Repo.insert(PendingFile.create_changeset(attrs))

        %PendingFile{status: :pending} = waiting ->
          Repo.update(PendingFile.rediscovered_changeset(waiting, attrs))

        decided ->
          {:ok, decided}
      end

    with {:ok, pending_file} <- result do
      Events.broadcast(%FileAdded{pending_file_id: pending_file.id})
      {:ok, pending_file}
    end
  end

  @doc """
  Adds files handed back by a rematch — each `%{file_path, media_dir}`
  is parsed for its metadata first. A rematch says the title was wrong,
  so the remembered matches for the names these files are read as are
  forgotten first; left in place, they would import the files to the
  same title on the next rescan. Returns `{:ok, count}` of files
  added; one that fails to save is logged and skipped.
  """
  @spec add_files_for_review([map()]) :: {:ok, non_neg_integer()}
  def add_files_for_review(files) do
    parsed = Enum.map(files, &parsed_pending_attrs/1)
    forget_names(parsed)

    added =
      Enum.count(parsed, fn attrs ->
        case reopen_for_review(attrs) do
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

  Terminal, the same way being linked is. `add_pending_file/1`
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
  Whether `file_path` has an approval Review has not yet seen linked. The
  approval owns the file's import — `settle_with_library/1` re-sends it if
  the first trip was lost — so Discovery leaves such a file alone rather
  than import it a second time.
  """
  @spec approved?(String.t()) :: boolean()
  def approved?(file_path) when is_binary(file_path) do
    Repo.exists?(
      from(p in PendingFile, where: p.file_path == ^file_path and p.status == :approved, limit: 1)
    )
  end

  @doc """
  Drops the queue rows for `file_paths` — the files are no longer
  library content, so there is no decision left to make about them.

  Status-blind on purpose: a `:dismissed` row is queue state too, and
  `add_pending_file/1` keys on `file_path` regardless of
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
  defp unlinked_message({:ingest_failed, _reason}),
    do: "Adding it to the library failed. Approve it again to retry."

  defp unlinked_message(:crashed), do: "Adding it to the library failed. Approve it again to retry."

  defp unlinked_message({:import_failed, :insufficient_disk_space}),
    do: "There isn't enough disk space to import it. Free some space and approve it again."

  defp unlinked_message({:import_failed, _reason}), do: "Importing it failed. Approve it again to retry."

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

  def destroy_pending_file(pending_file), do: Repo.delete(pending_file)

  def destroy_pending_file!(pending_file) do
    Repo.bang!(Repo.delete(pending_file))
    :ok
  end

  # ---------------------------------------------------------------------------
  # Business logic
  # ---------------------------------------------------------------------------

  @doc """
  The review page's list: every open item — `:pending`, awaiting a
  decision; `:approved`, awaiting its file's link outcome; `:dismissed`,
  restorable — ordered by parsed title (case-folded), then year, season,
  episode and path. Files the parser read the same way sit together
  whatever folder they came from; nothing groups them. The selection a
  person makes on the page is the unit of decision.
  """
  @spec list_queue() :: [PendingFile.t()]
  def list_queue do
    open(PendingFile)
    |> Repo.all()
    |> Enum.sort_by(fn file ->
      {String.downcase(file.parsed_title || ""), file.parsed_year || 0, file.parsed_season || 0,
       file.parsed_episode || 0, file.file_path}
    end)
  end

  @doc """
  Matches the items `ids` to one TMDB title and approves them in the same
  step: each item still `:pending` takes the title (`tmdb_id`,
  `tmdb_type`, `title`, `year`, `poster_path`), becomes `:approved` and is
  sent to Import. Items already approved or dismissed are left alone.

  `{:error, :no_identity}` when the title has no id or type — nothing is
  touched, since Import cannot place a file without both. Returns
  `{:ok, matched_count}` and broadcasts `FilesApproved`.
  """
  @spec match([Ecto.UUID.t()], map()) :: {:ok, non_neg_integer()} | {:error, :no_identity}
  def match(ids, %{tmdb_id: tmdb_id, tmdb_type: tmdb_type} = title) when is_list(ids) do
    if is_nil(tmdb_id) or tmdb_type not in ["movie", "tv"] do
      {:error, :no_identity}
    else
      attrs = %{
        tmdb_id: to_integer(tmdb_id),
        tmdb_type: tmdb_type,
        match_title: title[:title],
        match_year: title[:year] && to_string(title[:year]),
        match_poster_path: title[:poster_path],
        confidence: 1.0
      }

      approve_each(ids, &PendingFile.match_changeset(&1, attrs))
    end
  end

  @doc """
  Approves each `:pending` item in `ids` under its own best guess and
  sends it to Import — several unsure items whose guesses are right, each
  a different title, accepted in one press. An item with no guess is
  skipped and stays. Returns `{:ok, approved_count}` and broadcasts
  `FilesApproved`.
  """
  @spec approve([Ecto.UUID.t()]) :: {:ok, non_neg_integer()}
  def approve(ids) when is_list(ids), do: approve_each(ids, &PendingFile.approve_changeset/1)

  defp approve_each(ids, changeset_fun) do
    approved =
      for file <- pending_by_ids(ids),
          {:ok, approved} <- [Repo.update(changeset_fun.(file))] do
        Log.info(
          :review,
          "approved \"#{Path.basename(approved.file_path)}\" — tmdb:#{approved.tmdb_id} (#{approved.tmdb_type})"
        )

        send_to_import(approved)
        approved.id
      end

    if approved != [] do
      remember(Repo.all(from(p in PendingFile, where: p.id in ^approved)))
      Events.broadcast(%FilesApproved{pending_file_ids: approved})
    end

    {:ok, length(approved)}
  end

  defp pending_by_ids(ids),
    do:
      Repo.all(
        from(p in PendingFile, where: p.id in ^ids and p.status == :pending, order_by: p.file_path)
      )

  defp to_integer(id) when is_integer(id), do: id
  defp to_integer(id) when is_binary(id), do: String.to_integer(id)

  @doc """
  Dismisses each `:pending` item in `ids` — a person decided the file is
  not library content. Returns `{:ok, dismissed_count}`.
  """
  @spec dismiss([Ecto.UUID.t()]) :: {:ok, non_neg_integer()}
  def dismiss(ids) when is_list(ids) do
    dismissed =
      for file <- pending_by_ids(ids),
          {:ok, dismissed} <- [Repo.update(PendingFile.dismiss_changeset(file))] do
        Log.info(:review, "dismissed \"#{Path.basename(dismissed.file_path)}\"")
        broadcast_reviewed(dismissed.id)
      end

    {:ok, length(dismissed)}
  end

  @doc """
  Undoes the dismissal of each `:dismissed` item in `ids`: it returns to
  the queue as `:pending`, with the match it had. Broadcasts `FileAdded`
  per item. Returns `{:ok, restored_count}`.
  """
  @spec restore([Ecto.UUID.t()]) :: {:ok, non_neg_integer()}
  def restore(ids) when is_list(ids) do
    dismissed = Repo.all(from(p in PendingFile, where: p.id in ^ids and p.status == :dismissed))

    restored =
      for file <- dismissed, {:ok, restored} <- [Repo.update(PendingFile.restore_changeset(file))] do
        Log.info(:review, "restored \"#{Path.basename(restored.file_path)}\" — back in review")
        Events.broadcast(%FileAdded{pending_file_id: restored.id})
      end

    {:ok, length(restored)}
  end

  @doc """
  Deletes each item's file in `ids` from disk (and its
  `Library.FilePresence` row, via `Deletion.delete_file/1` — the primitive
  the title page uses), then its item — for files the user never wants,
  such as a broken download. Use this when no shared folder was found safe
  to delete wholesale (`MediaCentaur.DeleteTargets`); when one was, the
  caller deletes the folder itself and calls `destroy_pending_files/1`.
  Returns `{deleted_count, error_count}`.
  """
  @spec delete_files([Ecto.UUID.t()]) :: {non_neg_integer(), non_neg_integer()}
  def delete_files(ids) when is_list(ids) do
    results =
      for file <- Repo.all(from(p in PendingFile, where: p.id in ^ids)) do
        case Deletion.delete_file(file.file_path) do
          {:ok, _entity_ids} ->
            destroy_and_report(file)
            :ok

          {:error, reason} ->
            Log.warning(:review, "failed to delete #{file.file_path}: #{inspect(reason)}")
            :error
        end
      end

    {Enum.count(results, &(&1 == :ok)), Enum.count(results, &(&1 == :error))}
  end

  @doc """
  Destroys the items `ids` without touching disk — for when the caller has
  already deleted the containing folder (`Library.Deletion.delete_folder/2`,
  guarded by `MediaCentaur.DeleteTargets.resolve_folder_target/1`).
  """
  @spec destroy_pending_files([Ecto.UUID.t()]) :: :ok
  def destroy_pending_files(ids) when is_list(ids) do
    Enum.each(Repo.all(from(p in PendingFile, where: p.id in ^ids)), &destroy_and_report/1)
  end

  defp destroy_and_report(file) do
    {:ok, _} = destroy_pending_file(file)
    Log.info(:review, "deleted \"#{Path.basename(file.file_path)}\" — removed from review")
    broadcast_reviewed(file.id)
  end

  # Sends an approved file's match to Import. The message is a nudge for
  # latency: if it is lost, the approval is still stored and
  # `settle_with_library/1` sends it again.
  defp send_to_import(%PendingFile{} = pending_file) do
    Topics.publish(
      MediaCentaur.Topics.pipeline_matched(),
      {:file_matched,
       %{
         file_path: pending_file.file_path,
         media_dir: pending_file.media_directory,
         tmdb_id: pending_file.tmdb_id,
         tmdb_type: pending_file.tmdb_type
       }}
    )
  end

  # ---------------------------------------------------------------------------
  # Remembered matches
  # ---------------------------------------------------------------------------

  @doc """
  The answer a person gave for files named `title` (searched as
  `media_type`, with `year`), or `nil`. See `RememberedMatch` for how
  names compare.
  """
  @spec remembered_match(String.t(), :movie | :tv | :unknown, integer() | nil) ::
          RememberedMatch.t() | nil
  def remembered_match(title, media_type, year) when is_binary(title) do
    title
    |> name_query(to_string(media_type), year)
    |> Repo.one()
  end

  @doc "Every remembered match, by the name it was read as."
  @spec list_remembered_matches() :: [RememberedMatch.t()]
  def list_remembered_matches do
    RememberedMatch
    |> Repo.all()
    |> Enum.sort_by(&{String.downcase(&1.parsed_title), &1.parsed_year || 0, &1.media_type})
  end

  @doc "Forgets a remembered match; the next file with its name is searched on TMDB again."
  @spec forget_remembered_match(Ecto.UUID.t()) :: :ok
  def forget_remembered_match(id) do
    Repo.delete_all(from(r in RememberedMatch, where: r.id == ^id))
    :ok
  end

  # One answer per name: the latest replaces an earlier one.
  defp remember(files) do
    for file <- files, name = name_of(file), name != nil do
      {name, file}
    end
    |> Enum.uniq_by(fn {name, _file} -> name end)
    |> Enum.each(fn {{title_form, media_type, year}, file} ->
      Repo.transaction(fn ->
        Repo.delete_all(name_match(RememberedMatch, title_form, media_type, year))

        Repo.insert!(
          RememberedMatch.create_changeset(%{
            title_form: title_form,
            media_type: media_type,
            parsed_year: year,
            parsed_title: file.parsed_title,
            tmdb_id: file.tmdb_id,
            tmdb_type: file.tmdb_type,
            match_title: file.match_title,
            match_year: file.match_year,
            match_poster_path: file.match_poster_path
          })
        )
      end)
    end)
  end

  defp forget_names(parsed) do
    for attrs <- parsed, {title_form, media_type, year} <- [name_of(attrs)] do
      Repo.delete_all(name_match(RememberedMatch, title_form, media_type, year))
    end
  end

  # The name a file is remembered under, from its parsed columns, or nil
  # when the parser read no title.
  defp name_of(%{parsed_title: title} = parsed) when is_binary(title) and title != "" do
    type = parsed.parsed_type && String.to_existing_atom(parsed.parsed_type)

    media_type =
      Parser.effective_media_type(%Parser.Result{
        file_path: "",
        title: title,
        type: type || :unknown,
        season: Map.get(parsed, :parsed_season)
      })

    {TitleForm.compare(title), to_string(media_type), Map.get(parsed, :parsed_year)}
  end

  defp name_of(_parsed), do: nil

  defp name_query(title, media_type, year),
    do: name_match(RememberedMatch, TitleForm.compare(title), media_type, year)

  defp name_match(queryable, title_form, media_type, nil),
    do:
      from(r in queryable,
        where: r.title_form == ^title_form and r.media_type == ^media_type and is_nil(r.parsed_year)
      )

  defp name_match(queryable, title_form, media_type, year),
    do:
      from(r in queryable,
        where: r.title_form == ^title_form and r.media_type == ^media_type and r.parsed_year == ^year
      )

  defp broadcast_reviewed(file_id) do
    Events.broadcast(%FileReviewed{pending_file_id: file_id})
  end
end
