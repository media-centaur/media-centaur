defmodule MediaCentaur.Review do
  @moduledoc """
  The review domain — files requiring human review before library ingestion.

  Provides the `PendingFile` resource for tracking low-confidence matches.
  The ReviewLive UI reads PendingFile records for display and uses these
  functions for approve, dismiss, search, and match-selection workflows.

  Approval broadcasts a `{:review_resolved, ...}` event to `"pipeline:input"`,
  which the Pipeline Producer picks up for async processing via Broadway.
  """
  use Ash.Domain, extensions: [AshAi]

  tools do
    tool :read_pending_files, MediaCentaur.Review.PendingFile, :pending do
      description "List files pending human review before library ingestion"
    end

    tool :approve_pending_file, MediaCentaur.Review.PendingFile, :approve do
      description "Approve a pending file for library ingestion"
    end

    tool :dismiss_pending_file, MediaCentaur.Review.PendingFile, :dismiss do
      description "Dismiss a pending file (skip ingestion)"
    end

    tool :set_pending_file_match, MediaCentaur.Review.PendingFile, :set_tmdb_match do
      description "Set the TMDB match on a pending file (tmdb_id, confidence, match_title, match_year, match_poster_path)"
    end

    tool :destroy_pending_file, MediaCentaur.Review.PendingFile, :destroy do
      description "Delete a pending file record"
    end

    tool :search_tmdb, MediaCentaur.Review.PendingFile, :search_tmdb do
      description "Search TMDB for a movie or TV show by title"
    end
  end

  resources do
    resource MediaCentaur.Review.PendingFile do
      define :list_pending_files, action: :read
      define :get_pending_file, action: :read, get_by: [:id]
      define :list_pending_files_for_review, action: :pending
      define :create_pending_file, action: :create
      define :find_or_create_pending_file, action: :find_or_create
      define :approve_pending_file, action: :approve
      define :dismiss_pending_file, action: :dismiss
      define :set_pending_file_match, action: :set_tmdb_match
      define :destroy_pending_file, action: :destroy
    end
  end

  require Logger
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.DateUtil

  def fetch_pending_files do
    __MODULE__.list_pending_files_for_review!()
  end

  @doc """
  Groups pending files by series root — the first directory component below
  the watch directory. Two files share a group when they have the same
  `{watch_directory, series_root}`.

  Returns a list of group maps:

      %{key: {watch_dir, root}, files: [pending_files], representative: first_file}

  Single-file groups (movies, flat downloads) are groups of 1 — same shape.
  """
  def fetch_pending_groups do
    fetch_pending_files()
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

      /media/tv/Sample Show One (2001)/Season 1/ep.mkv  →  "Sample Show One (2001)"
      /media/movies/movie.mkv                   →  "movie.mkv"
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
    Log.info(:library, "approving #{pending_file.id}")

    with {:ok, pending_file} <- __MODULE__.approve_pending_file(pending_file) do
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        "pipeline:input",
        {:review_resolved,
         %{
           path: pending_file.file_path,
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
    result = __MODULE__.dismiss_pending_file(pending_file)
    if match?({:ok, _}, result), do: broadcast_reviewed(pending_file.id)
    result
  end

  def set_tmdb_match(pending_file, %{
        tmdb_id: tmdb_id,
        title: title,
        year: year,
        poster_path: poster_path
      }) do
    tmdb_id_int =
      case tmdb_id do
        id when is_integer(id) -> id
        id when is_binary(id) -> String.to_integer(id)
      end

    __MODULE__.set_pending_file_match(pending_file, %{
      tmdb_id: tmdb_id_int,
      match_title: title,
      match_year: year,
      match_poster_path: poster_path,
      confidence: 1.0
    })
  end

  def search_tmdb(query, type) do
    Log.info(:library, "manual search: #{inspect(query)} type: #{type}")
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
    Phoenix.PubSub.broadcast(MediaCentaur.PubSub, "review:updates", {:file_reviewed, file_id})
  end
end
