defmodule MediaManager.Review do
  @moduledoc """
  The review domain — files requiring human review before library ingestion.

  Provides the `PendingFile` resource for tracking low-confidence matches.
  The ReviewLive UI reads PendingFile records for display and uses these
  functions for approve, dismiss, search, and match-selection workflows.
  """
  use Ash.Domain

  resources do
    resource MediaManager.Review.PendingFile
  end

  require Logger
  require MediaManager.Log, as: Log

  alias MediaManager.Library.Helpers
  alias MediaManager.Parser
  alias MediaManager.Pipeline.Payload

  alias MediaManager.Pipeline.Stages.{
    FetchMetadata,
    DownloadImages,
    Ingest
  }

  alias MediaManager.Review.PendingFile
  alias MediaManager.TMDB.Client
  alias MediaManager.DateUtil

  def fetch_pending_files do
    Ash.read!(PendingFile, action: :pending)
  end

  def approve_and_process(pending_file) do
    Task.Supervisor.start_child(MediaManager.TaskSupervisor, fn ->
      process_approval(pending_file)
    end)
  end

  defp process_approval(pending_file) do
    Log.info(:library, "processing approval for #{pending_file.id}")

    with {:ok, pending_file} <- approve(pending_file),
         {:ok, _payload} <- run_approved_pipeline(pending_file) do
      Ash.destroy!(pending_file)
      broadcast_reviewed(pending_file.id)
    else
      {:error, reason} ->
        Logger.error("Review approval failed for #{pending_file.id}: #{inspect(reason)}")
        broadcast_reviewed(pending_file.id)
    end
  end

  defp approve(pending_file) do
    Ash.update(pending_file, %{}, action: :approve)
  end

  defp run_approved_pipeline(pending_file) do
    payload = %Payload{
      file_path: pending_file.file_path,
      watch_directory: pending_file.watch_directory,
      entry_point: :review_resolved,
      parsed: Parser.parse(pending_file.file_path),
      tmdb_id: pending_file.tmdb_id,
      tmdb_type: String.to_existing_atom(pending_file.tmdb_type),
      confidence: pending_file.confidence,
      match_title: pending_file.match_title,
      match_year: pending_file.match_year,
      match_poster_path: pending_file.match_poster_path
    }

    with {:ok, payload} <- FetchMetadata.run(payload),
         {:ok, payload} <- DownloadImages.run(payload),
         {:ok, payload} <- Ingest.run(payload) do
      Helpers.broadcast_entities_changed([payload.entity_id])
      {:ok, payload}
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
    Phoenix.PubSub.broadcast(MediaManager.PubSub, "review:updates", {:file_reviewed, file_id})
  end
end
