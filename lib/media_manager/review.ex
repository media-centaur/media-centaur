defmodule MediaManager.Review do
  @moduledoc """
  Data-fetching and processing module for the review approval workflow.
  Keeps the LiveView thin by centralizing all review queries and actions.
  """

  alias MediaManager.Library.WatchedFile
  alias MediaManager.TMDB.Client

  def fetch_pending_files do
    Ash.read!(WatchedFile, action: :pending_review_files)
  end

  def approve_and_process(file) do
    Task.Supervisor.start_child(MediaManager.TaskSupervisor, fn ->
      process_approval(file)
    end)
  end

  defp process_approval(file) do
    with {:ok, file} <- approve(file),
         {:ok, file} <- fetch_metadata(file),
         {:ok, _file} <- maybe_download_images(file) do
      broadcast_reviewed(file.id)
      if file.entity_id, do: broadcast_entity_changed(file.entity_id)
    else
      {:error, reason} ->
        require Logger
        Logger.error("Review approval failed for #{file.id}: #{inspect(reason)}")
        broadcast_reviewed(file.id)
    end
  end

  defp approve(file) do
    file
    |> Ash.Changeset.for_update(:approve, %{})
    |> Ash.update()
  end

  defp fetch_metadata(file) do
    file
    |> Ash.Changeset.for_update(:fetch_metadata, %{})
    |> Ash.update()
  end

  defp maybe_download_images(file) do
    if file.state == :fetching_images do
      file
      |> Ash.Changeset.for_update(:download_images, %{})
      |> Ash.update()
    else
      {:ok, file}
    end
  end

  def dismiss(file) do
    result =
      file
      |> Ash.Changeset.for_update(:dismiss, %{})
      |> Ash.update()

    case result do
      {:ok, _file} -> broadcast_reviewed(file.id)
      _ -> :ok
    end

    result
  end

  def set_tmdb_match(file, %{tmdb_id: tmdb_id, title: title, year: year, poster_path: poster_path}) do
    file
    |> Ash.Changeset.for_update(:set_tmdb_match, %{
      tmdb_id: to_string(tmdb_id),
      match_title: title,
      match_year: year,
      match_poster_path: poster_path,
      confidence_score: 1.0
    })
    |> Ash.update()
  end

  def search_tmdb(query, type) do
    search_fn = if type == :tv, do: &Client.search_tv/2, else: &Client.search_movie/2
    title_key = if type == :tv, do: "name", else: "title"
    year_key = if type == :tv, do: "first_air_date", else: "release_date"

    case search_fn.(query, nil) do
      {:ok, results} ->
        normalized =
          results
          |> Enum.take(10)
          |> Enum.map(fn result ->
            %{
              tmdb_id: to_string(result["id"]),
              title: result[title_key],
              year: extract_year(result[year_key]),
              overview: result["overview"],
              poster_path: result["poster_path"]
            }
          end)

        {:ok, normalized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_year(nil), do: nil
  defp extract_year(""), do: nil
  defp extract_year(<<year::binary-size(4), _rest::binary>>), do: year

  defp broadcast_reviewed(file_id) do
    Phoenix.PubSub.broadcast(MediaManager.PubSub, "review:updates", {:file_reviewed, file_id})
  end

  defp broadcast_entity_changed(entity_id) do
    Phoenix.PubSub.broadcast(
      MediaManager.PubSub,
      "library:updates",
      {:entities_changed, [entity_id]}
    )
  end
end
