defmodule MediaCentaur.ReleaseTracking.Onboarding do
  @moduledoc """
  Builds the machinery a followed title needs: ensures the title (and the
  seasons its calendar wants) is in the TMDB store, creates the
  tracked-title row, seeds its calendar from the stored payloads, catches
  the person up, syncs the wants, and queues its artwork.

  Called from exactly one place — `ReleaseTracking.set_rung/3`, when a
  rung of `:follow` or above finds no tracked title. It is a derivation
  step, not an act: a person raising a rung is the act, and the context
  announces that. Nothing here decides *whether* a title is followed.

  **Follow means caught up as of now** (campaign `discovery.md`, decision
  6): a series' calendar is seeded with every episode the wanted seasons
  hold, aired ones included, and the person's caught-up point is then set
  to TMDB's latest aired episode (`Calendar.latest_aired/1`, written
  through `ReleaseTracking.catch_up/2`'s record half), so the aired
  episodes are *had* and open no want. What was aired before the person
  followed is the Download button's business, not the ledger's. The
  first rebuild therefore finds the calendar it would have built.

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
  alias MediaCentaur.ReleaseTracking.{Calendar, Had, Helpers, Wants}
  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Watchlist

  @doc "Creates the tracked title for `title` and everything under it."
  @spec onboard(Title.t()) :: {:ok, ReleaseTracking.Item.t()} | {:error, term()}
  def onboard(%Title{} = title) do
    case do_onboard(title) do
      {:ok, item} ->
        ReleaseTracking.broadcast_releases_updated([item.id])
        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_onboard(%Title{media_type: :tv_series} = title) do
    with {:ok, record} <- Store.ensure({title.tmdb_id, :tv_series}),
         {:ok, item} <- track(%{tmdb_id: title.tmdb_id, media_type: :tv_series}) do
      point = Had.point(item, Watchlist.caught_up(item.tmdb_id, :tv_series))
      season_payloads = ensure_seasons(item, record, elem(point, 0))
      releases = Calendar.tv_releases(record.payload, season_payloads, point)

      ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_release!/2)
      catch_up(item, record.payload)
      ReleaseTracking.mark_in_library_releases(item)
      Wants.sync_item(item)
      Helpers.download_images_async(item, title.tmdb_id, record.payload)
      {:ok, item}
    end
  end

  defp do_onboard(%Title{media_type: :movie} = title) do
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

  # Follow means caught up as of now: the point lands on the latest aired
  # episode. A series TMDB has aired nothing of yet has no point to set.
  defp catch_up(item, payload) do
    with latest when latest != nil <- Calendar.latest_aired(payload),
         {:error, reason} <- Watchlist.catch_up(item.tmdb_id, :tv_series, latest) do
      # The record went Off between the rung write and this derivation;
      # the machinery is dropped by the next derivation, nothing to set.
      Log.info(:acquisition, "tmdb:#{item.tmdb_id} not caught up on follow — #{inspect(reason)}")
    end

    :ok
  end

  # The seasons the calendar wants, first-contacted when the store lacks
  # them; one that TMDB cannot answer is left out of this seeding and
  # picked up by the next rebuild.
  defp ensure_seasons(item, record, point_season) do
    record.payload
    |> Calendar.seasons_wanted(point_season)
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

  defp persist_movie_releases(item, releases) do
    ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_movie_release!/2)

    Wants.sync_item(item)
  end
end
