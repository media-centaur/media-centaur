defmodule MediaCentarr.Review do
  use Boundary, deps: [MediaCentarr.TMDB], exports: [Rematch]

  @moduledoc """
  The review domain — files requiring human review before library ingestion.

  Provides the `PendingFile` resource for tracking low-confidence matches.
  The ReviewLive UI reads PendingFile records for display and uses these
  functions for approve, dismiss, search, and match-selection workflows.

  Approval broadcasts a `{:file_matched, ...}` event to `MediaCentarr.Topics.pipeline_matched()`,
  which the Import Pipeline Producer picks up for async processing via Broadway.
  """
  import Ecto.Query

  alias MediaCentarr.Repo
  alias MediaCentarr.Review.PendingFile

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Topics
  alias MediaCentarr.TMDB.Client
  alias MediaCentarr.DateUtil

  @doc "Subscribe the caller to review process events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.review_updates())
  end

  # ---------------------------------------------------------------------------
  # PendingFile CRUD
  # ---------------------------------------------------------------------------

  def list_pending_files, do: Repo.all(PendingFile)

  def get_pending_file(id) do
    case Repo.get(PendingFile, id) do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  end

  def get_pending_file!(id), do: Repo.get!(PendingFile, id)

  def list_pending_files_for_review do
    Repo.all(
      from(p in PendingFile,
        where: p.status == :pending,
        order_by: [asc: p.inserted_at]
      )
    )
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

  def approve_pending_file(pending_file) do
    Repo.update(PendingFile.approve_changeset(pending_file))
  end

  def approve_pending_file!(pending_file), do: Repo.bang!(approve_pending_file(pending_file))

  def dismiss_pending_file(pending_file) do
    Repo.update(PendingFile.dismiss_changeset(pending_file))
  end

  def dismiss_pending_file!(pending_file), do: Repo.bang!(dismiss_pending_file(pending_file))

  def set_pending_file_match(pending_file, attrs) do
    Repo.update(PendingFile.set_tmdb_match_changeset(pending_file, attrs))
  end

  def set_pending_file_match!(pending_file, attrs) do
    Repo.bang!(set_pending_file_match(pending_file, attrs))
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
  the watch directory. Two files share a group when they have the same
  `{watch_directory, series_root}`.

  Returns a list of group maps:

      %{key: {watch_dir, root}, files: [pending_files], representative: first_file}

  Single-file groups (movies, flat downloads) are groups of 1 — same shape.
  """
  def fetch_pending_groups do
    list_pending_files_for_review()
    |> Enum.group_by(fn file ->
      {file.watch_directory, series_root(file)}
    end)
    |> Enum.map(fn {key, files} ->
      %{key: key, files: files, representative: hd(files)}
    end)
  end

  @doc """
  Extracts the series root — the first path component below the watch directory.

  Examples:

      /media/tv/Sample Show (2001)/Season 1/ep.mkv  ->  "Sample Show (2001)"
      /media/movies/movie.mkv                   ->  "movie.mkv"
  """
  def series_root(%{file_path: file_path, watch_directory: nil}), do: file_path

  def series_root(%{file_path: file_path, watch_directory: watch_dir}) do
    relative = String.replace_prefix(file_path, watch_dir <> "/", "")

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
  Sets the TMDB match on all files in a group.
  Returns `{updated_count, error_count}`.
  """
  def set_group_match(files, match) do
    results = Enum.map(files, &set_tmdb_match(&1, match))
    updated = Enum.count(results, &match?({:ok, _}, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))
    {updated, errors}
  end

  def approve_and_process(pending_file) do
    Log.info(
      :library,
      "approved \"#{Path.basename(pending_file.file_path)}\" — tmdb:#{pending_file.tmdb_id} (#{pending_file.tmdb_type})"
    )

    with {:ok, pending_file} <- approve_pending_file(pending_file) do
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.pipeline_matched(),
        {:file_matched,
         %{
           file_path: pending_file.file_path,
           watch_dir: pending_file.watch_directory,
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
      Log.info(:library, "dismissed \"#{Path.basename(pending_file.file_path)}\"")
      broadcast_reviewed(pending_file.id)
    end

    result
  end

  def set_tmdb_match(pending_file, %{
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

  def search_tmdb(query, type) do
    Log.info(:library, "manual search — #{query} (#{type})")
    search_fn = if type == :tv, do: &Client.search_tv/2, else: &Client.search_movie/2
    title_key = if type == :tv, do: "name", else: "title"
    year_key = if type == :tv, do: "first_air_date", else: "release_date"
    cleaned_query = clean_search_query(query)

    case search_fn.(cleaned_query, nil) do
      {:ok, results} ->
        normalized =
          results
          |> Enum.take(10)
          |> Enum.map(fn result ->
            %{
              tmdb_id: to_string(result["id"]),
              title: result[title_key],
              year: DateUtil.extract_year(result[year_key]),
              overview: result["overview"],
              poster_path: result["poster_path"]
            }
          end)

        {:ok, normalized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp clean_search_query(query) do
    query
    |> String.replace(~r/[Ss]\d{1,2}[Ee]\d{1,2}/, "")
    |> String.replace(~r/[Ss]eason\s*\d+/i, "")
    |> String.replace(~r/[Ee]pisode\s*\d+/i, "")
    |> String.replace(~r/[Ee]\d{2,}/, "")
    |> String.trim()
  end

  defp broadcast_reviewed(file_id) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.review_updates(),
      {:file_reviewed, file_id}
    )
  end
end
