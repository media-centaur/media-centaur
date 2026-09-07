defmodule MediaCentaur.ReleaseTracking.Onboarding do
  @moduledoc """
  Builds the machinery a followed title needs: fetches the title from
  TMDB, creates the tracked-title row, seeds its calendar and wants, and
  queues its artwork.

  Called from exactly one place — `ReleaseTracking.set_rung/3`, when a
  rung of `:follow` or above finds no tracked title. It is a derivation
  step, not an act: a person raising a rung is the act, and the context
  announces that. Nothing here decides *whether* a title is followed.

  It was `ReleaseTracking.Acquisition`, which collided with the
  `MediaCentaur.Acquisition` context — two unrelated meanings for one
  word. Title search itself lives in `MediaCentaur.TMDB.TitleSearch`.

  Persistence and event creation route back through the context
  (`track_item`, `persist_release!`, `create_release!`,
  `mark_in_library_releases`, `create_event!`, `update_item`,
  `broadcast_releases_updated`), which own those concerns.
  """

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Extractor, Helpers, Release, Wants}
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.TMDB.Title

  @doc """
  Creates the tracked title for `title` and everything under it.

  `opts` may carry `:start_season` / `:start_episode` to scope the first
  TV calendar fetch — `{0, 0}` (the default) means "only what is still to
  come", and an explicit start includes what has already aired.
  """
  @spec onboard(Title.t(), map()) :: {:ok, ReleaseTracking.Item.t()} | {:error, term()}
  def onboard(%Title{} = title, opts \\ %{}) do
    start_season = Map.get(opts, :start_season, 0)
    start_episode = Map.get(opts, :start_episode, 0)

    case do_onboard(title, start_season, start_episode) do
      {:ok, item} ->
        ReleaseTracking.broadcast_releases_updated([item.id])
        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_onboard(%Title{media_type: :tv_series} = title, start_season, start_episode) do
    case Client.get_tv(title.tmdb_id) do
      {:ok, response} ->
        all_releases =
          Helpers.fetch_tv_releases(title.tmdb_id, start_season, start_episode, response)

        # "All upcoming" (0,0) = only future episodes. Custom scope = include released too.
        releases =
          if start_season == 0 && start_episode == 0 do
            Enum.reject(all_releases, &Release.released?/1)
          else
            all_releases
          end

        case ReleaseTracking.track_item(%{
               tmdb_id: title.tmdb_id,
               media_type: :tv_series,
               name: response["name"] || title.name,
               last_refreshed_at: DateTime.utc_now(),
               last_library_season: start_season,
               last_library_episode: start_episode
             }) do
          {:ok, item} ->
            persist_releases(item, releases)
            create_began_tracking_event(item)
            schedule_image_downloads(item, title.tmdb_id, response)

            {:ok, item}

          {:error, changeset} ->
            {:error, track_item_error(changeset)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_onboard(%Title{media_type: :movie} = title, _start_season, _start_episode) do
    case Client.get_movie(title.tmdb_id) do
      {:ok, response} ->
        case ReleaseTracking.track_item(%{
               tmdb_id: title.tmdb_id,
               media_type: :movie,
               name: response["title"] || title.name,
               last_refreshed_at: DateTime.utc_now()
             }) do
          {:ok, item} ->
            releases = Extractor.extract_movie_release_dates(response)
            persist_movie_releases(item, releases)

            create_began_tracking_event(item)
            schedule_image_downloads(item, title.tmdb_id, response)

            {:ok, item}

          {:error, changeset} ->
            {:error, track_item_error(changeset)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A duplicate track attempt (double click, stale search results, two
  # in-flight async tracks) hits the {tmdb_id, media_type} unique
  # constraint — an expected no-op, not a fault. Anything else is a
  # genuine changeset failure the caller should see.
  defp track_item_error(changeset) do
    duplicate? =
      Enum.any?(changeset.errors, fn
        {:tmdb_id, {_message, meta}} -> meta[:constraint] == :unique
        _other -> false
      end)

    if duplicate?, do: :already_tracked, else: changeset
  end

  defp persist_releases(item, releases) do
    ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_release!/2)

    ReleaseTracking.mark_in_library_releases(item)
    Wants.sync_item(item)
  end

  defp persist_movie_releases(item, releases) do
    ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_movie_release!/2)

    Wants.sync_item(item)
  end

  defp create_began_tracking_event(item) do
    ReleaseTracking.create_event!(%{
      item_id: item.id,
      item_name: item.name,
      event_type: :began_tracking,
      description: "Now tracking #{item.name}"
    })
  end

  defp schedule_image_downloads(item, tmdb_id, response),
    do: Helpers.download_images_async(item, tmdb_id, response)
end
