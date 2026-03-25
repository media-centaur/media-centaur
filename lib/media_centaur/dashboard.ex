defmodule MediaCentaur.Dashboard do
  @moduledoc """
  Data-fetching module for the admin dashboard.
  Keeps the LiveView thin by centralizing all dashboard queries.
  """
  import Ecto.Query

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{Entity, Episode, WatchedFile, Image}
  alias MediaCentaur.Pipeline.Stats
  alias MediaCentaur.Repo
  alias MediaCentaur.Review

  def fetch_stats do
    %{
      library: fetch_library_stats(),
      pending_review: fetch_pending_review(),
      recent_errors: fetch_recent_errors(),
      recent_changes: fetch_recent_changes(),
      recently_watched: fetch_recently_watched()
    }
  end

  def fetch_recent_changes do
    days = MediaCentaur.Config.get(:recent_changes_days) || 3
    since = DateTime.add(DateTime.utc_now(), -days, :day)
    Library.list_recent_changes!(10, since)
  end

  def fetch_recently_watched do
    limit = MediaCentaur.Config.get(:recently_watched_count) || 5
    Library.list_recently_watched!(limit)
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

  defp count(schema, filter \\ []) do
    query = from(r in schema, select: count(r.id))

    query =
      Enum.reduce(filter, query, fn {key, value}, q ->
        from(r in q, where: field(r, ^key) == ^value)
      end)

    Repo.one(query)
  end
end
