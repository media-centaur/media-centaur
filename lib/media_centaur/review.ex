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
  end

  resources do
    resource MediaCentaur.Review.PendingFile
  end

  require Logger
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Review.PendingFile
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.DateUtil

  def fetch_pending_files do
    Ash.read!(PendingFile, action: :pending)
  end

  def approve_and_process(pending_file) do
    Log.info(:library, "approving #{pending_file.id}")

    with {:ok, pending_file} <- Ash.update(pending_file, %{}, action: :approve) do
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
    result = Ash.update(pending_file, %{}, action: :dismiss)
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

    Ash.update(
      pending_file,
      %{
        tmdb_id: tmdb_id_int,
        match_title: title,
        match_year: year,
        match_poster_path: poster_path,
        confidence: 1.0
      },
      action: :set_tmdb_match
    )
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
