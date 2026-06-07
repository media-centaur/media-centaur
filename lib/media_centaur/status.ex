defmodule MediaCentaur.Status do
  use Boundary, top_level?: true, check: [in: false, out: false]

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

  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Library.Completeness
  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Maintenance
  alias MediaCentaur.Repo
  alias MediaCentaur.Review
  alias MediaCentaur.Status.LibraryOverview

  def fetch_stats do
    %{
      library: fetch_library_stats(),
      pending_review: fetch_pending_review(),
      recent_changes: fetch_recent_changes()
    }
  end

  @recently_added_limit 12

  @doc """
  Builds the `LibraryOverview` view-model for the Status page's "Your
  library" section — counts, size, recent additions, pending work and
  completeness gaps composed across the Library, Review, Acquisition and
  Maintenance contexts.

  Runs several reads including a per-image disk check
  (`Maintenance.missing_images_summary/0`), so callers must invoke it off
  the LiveView mount path (e.g. via `start_async/3`), never inside `mount`.
  """
  @spec fetch_overview() :: LibraryOverview.t()
  def fetch_overview do
    stats = fetch_library_stats()

    %LibraryOverview{
      movie_count: stats.by_type.movie,
      show_count: stats.by_type.tv_series,
      episode_count: stats.episodes,
      total_size_bytes: FilePresence.total_size_bytes(),
      recently_added: Library.list_recently_added(limit: @recently_added_limit),
      pending_review_count: length(Review.list_pending_files_for_review()),
      in_flight_count: length(Pursuits.list_active()),
      missing_artwork_count: Maintenance.missing_images_summary().missing,
      missing_metadata_count: Completeness.missing_metadata_count(),
      incomplete_season_count: Completeness.incomplete_season_count()
    }
  end

  def fetch_recent_changes do
    days = MediaCentaur.Config.get(:recent_changes_days) || 3
    since = DateTime.add(DateTime.utc_now(), -days, :day)
    Library.list_recent_changes(10, since)
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
    Enum.take(Review.list_pending_files_for_review(), 20)
  end

  defp count(schema) do
    Repo.one(from(r in schema, select: count(r.id)))
  end
end
