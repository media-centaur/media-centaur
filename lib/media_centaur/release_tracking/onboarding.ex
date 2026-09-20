defmodule MediaCentaur.ReleaseTracking.Onboarding do
  @moduledoc """
  Builds the machinery a followed title needs: ensures the title (and the
  seasons its calendar wants) is in the TMDB store, creates the
  tracked-title row, seeds its calendar and wants from the stored
  payloads, and queues its artwork.

  Called from exactly one place — `ReleaseTracking.set_rung/3`, when a
  rung of `:follow` or above finds no tracked title. It is a derivation
  step, not an act: a person raising a rung is the act, and the context
  announces that. Nothing here decides *whether* a title is followed.

  The only request it can cause is first contact for a title or season
  the store does not hold (`TMDB.Store.ensure/2`, ADR-071); a title the
  store holds costs nothing. Later changes reach the calendar through
  `ReleaseTracking.rebuild_calendar/1`, not here.

  It was `ReleaseTracking.Acquisition`, which collided with the
  `MediaCentaur.Acquisition` context — two unrelated meanings for one
  word. Title search itself lives in `MediaCentaur.TMDB.TitleSearch`.

  Persistence routes back through the context (`track_item`,
  `persist_release!`, `create_release!`, `mark_in_library_releases`,
  `broadcast_releases_updated`), which owns those concerns.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Calendar, Helpers, Release, Wants}
  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.TMDB.Title

  @doc """
  Creates the tracked title for `title` and everything under it.

  `opts` may carry `:start_season` / `:start_episode` to scope the first
  TV calendar — `{0, 0}` (the default) means "only what is still to
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
    with {:ok, record} <- Store.ensure({title.tmdb_id, :tv_series}),
         {:ok, item} <-
           track(%{
             tmdb_id: title.tmdb_id,
             media_type: :tv_series,
             last_library_season: start_season,
             last_library_episode: start_episode
           }) do
      season_payloads = ensure_seasons(item, record)

      all_releases =
        Calendar.tv_releases(record.payload, season_payloads, start_season, start_episode)

      # "All upcoming" (0,0) = only future episodes. Custom scope = include released too.
      releases =
        if start_season == 0 and start_episode == 0,
          do: Enum.reject(all_releases, &Release.released?/1),
          else: all_releases

      persist_releases(item, releases)
      Helpers.download_images_async(item, title.tmdb_id, record.payload)
      {:ok, item}
    end
  end

  defp do_onboard(%Title{media_type: :movie} = title, _start_season, _start_episode) do
    with {:ok, record} <- Store.ensure({title.tmdb_id, :movie}),
         {:ok, item} <- track(%{tmdb_id: title.tmdb_id, media_type: :movie}) do
      persist_movie_releases(item, Calendar.movie_releases(record.payload))
      Helpers.download_images_async(item, title.tmdb_id, record.payload)
      {:ok, item}
    end
  end

  defp track(attrs) do
    case ReleaseTracking.track_item(attrs) do
      {:ok, item} -> {:ok, item}
      {:error, changeset} -> {:error, track_item_error(changeset)}
    end
  end

  # The seasons the calendar wants, first-contacted when the store lacks
  # them; one that TMDB cannot answer is left out of this seeding and
  # picked up by the next rebuild.
  defp ensure_seasons(item, record) do
    record.payload
    |> Calendar.seasons_wanted(item.last_library_season)
    |> Enum.each(fn season_number ->
      case Store.ensure_season(item.tmdb_id, season_number) do
        {:ok, _season} ->
          :ok

        {:error, reason} ->
          Log.info(
            :acquisition,
            "season tmdb:#{item.tmdb_id} S#{season_number} not stored — #{inspect(reason)}"
          )
      end
    end)

    item.tmdb_id |> Store.seasons() |> Enum.map(& &1.payload)
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
end
