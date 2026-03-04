defmodule MediaCentaur.Dashboard do
  @moduledoc """
  Data-fetching module for the admin dashboard.
  Keeps the LiveView thin by centralizing all dashboard queries.
  """

  alias MediaCentaur.Library.{Entity, Episode, WatchedFile, Image}
  alias MediaCentaur.Pipeline.Stats
  alias MediaCentaur.Review

  def fetch_stats do
    %{
      library: fetch_library_stats(),
      pending_review: fetch_pending_review(),
      recent_errors: fetch_recent_errors()
    }
  end

  def fetch_library_stats do
    episode_count = count(Episode)
    file_count = count(WatchedFile)
    image_count = count(Image)

    type_counts = %{
      movie: count(Entity, type: :movie),
      tv_series: count(Entity, type: :tv_series),
      movie_series: count(Entity, type: :movie_series),
      video_object: count(Entity, type: :video_object)
    }

    %{
      episodes: episode_count,
      files: file_count,
      images: image_count,
      by_type: type_counts
    }
  end

  def fetch_pending_review do
    Review.list_pending_files_for_review!()
    |> Enum.take(20)
  end

  def fetch_recent_errors do
    Stats.get_snapshot().recent_errors
  end

  defp count(queryable, filter \\ []) do
    opts = if filter == [], do: [], else: [query: [filter: filter]]

    case Ash.count(queryable, opts) do
      {:ok, n} -> n
      _ -> 0
    end
  end
end
