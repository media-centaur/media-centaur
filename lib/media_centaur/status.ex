defmodule MediaCentaur.Status do
  @moduledoc """
  Data-fetching module for the operational Status page.

  Keeps `StatusLive` thin by centralizing all of the read queries the status
  page needs — library counts, pending review, recent errors, and the recent
  changes feed.
  """
  import Ecto.Query

  alias MediaCentaur.Library

  alias MediaCentaur.Library.{
    Episode,
    Movie,
    MovieSeries,
    TVSeries,
    VideoObject,
    WatchedFile,
    Image
  }

  alias MediaCentaur.Pipeline.Stats
  alias MediaCentaur.Repo
  alias MediaCentaur.Review

  def fetch_stats do
    %{
      library: fetch_library_stats(),
      pending_review: fetch_pending_review(),
      recent_errors: fetch_recent_errors(),
      recent_changes: fetch_recent_changes(),
      recently_watched: []
    }
  end

  def fetch_recent_changes do
    days = MediaCentaur.Config.get(:recent_changes_days) || 3
    since = DateTime.add(DateTime.utc_now(), -days, :day)
    Library.list_recent_changes!(10, since)
  end

  def fetch_library_stats do
    episode_count = count(Episode)
    file_count = count(WatchedFile)
    image_count = count(Image)

    type_counts = %{
      movie: Repo.one(from m in Movie, where: is_nil(m.movie_series_id), select: count(m.id)),
      tv_series: count(TVSeries),
      movie_series: count(MovieSeries),
      video_object: count(VideoObject)
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

  defp count(schema) do
    Repo.one(from(r in schema, select: count(r.id)))
  end
end
