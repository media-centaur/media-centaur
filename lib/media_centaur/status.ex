defmodule MediaCentaur.Status do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Read-side aggregator for the operational Status page.

  Keeps `StatusLive` thin by composing the context facades the status page
  needs — library counts, pending review, and the recent changes feed. All
  persistence stays behind those facades; this module owns no queries of its
  own.

  > Boundary follow-up: `check: false` is a holdover from when this module ran
  > raw schema queries. Now that it only composes facades it can declare
  > `deps: [...]` and re-enable the check — deferred because that also requires
  > exporting `Library.Completeness` and listing the composed contexts.
  """

  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Completeness
  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Maintenance
  alias MediaCentaur.Review
  alias MediaCentaur.Status.LibraryOverview

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

  def fetch_library_stats, do: Library.stats()
end
