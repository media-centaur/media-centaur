defmodule MediaCentaur.Pipeline.TmdbProjection do
  @moduledoc """
  The library's TMDB fields are a projection of the TMDB store (ADR-071,
  design §2.6). Subscribes to `MediaCentaur.Topics.tmdb_titles/0`; on
  `{:tmdb_title_changed, ref}` re-applies `TMDB.Mapper`'s output to the
  owned movie or series — every field the mapper derives except the
  credits (fetched whole once, at import; the store does not keep them)
  and the collection facts — and, for a series, rebuilds each library
  season's episode list and each episode's name, overview, runtime and
  air date from the stored season. A season the store lacks is
  first-contacted when it is open (the series' latest, or one whose list
  names an undated or future episode); a closed one it never held stays
  as imported.

  Lives in the pipeline, the library's TMDB-facing side: `Library`
  depends on nothing TMDB-shaped (ADR-029). Subscribe-and-dispatch only;
  skipped in `:test`, where tests call `reapply/1` directly.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{Containers, Episodes, ExternalIds, Movie, Seasons, TVSeries}
  alias MediaCentaur.TMDB.{Mapper, Store}
  alias MediaCentaur.Topics

  # What `Mapper.*_attrs` derive, minus the credits and the collection facts.
  @movie_fields [
    :name,
    :description,
    :date_published,
    :duration_seconds,
    :director,
    :content_rating,
    :url,
    :aggregate_rating_value,
    :vote_count,
    :tagline,
    :original_language,
    :studio,
    :country_code,
    :genres,
    :status
  ]

  @series_fields [
    :name,
    :description,
    :date_published,
    :genres,
    :url,
    :aggregate_rating_value,
    :vote_count,
    :tagline,
    :original_language,
    :studio,
    :country_code,
    :network,
    :number_of_seasons,
    :status
  ]

  @episode_fields [:name, :description, :duration_seconds, :date_published]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Topics.subscribe(Topics.tmdb_titles())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:tmdb_title_changed, ref}, state) do
    reapply(ref)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc """
  Re-applies the stored title to the library entity that owns it. A
  title the library does not own, or the store does not hold, is a
  no-op.
  """
  @spec reapply(Store.ref()) :: :ok
  def reapply({tmdb_id, :movie} = ref) do
    with %Movie{} = movie <- ExternalIds.find_by_external_id(:movie, to_string(tmdb_id)),
         %{payload: payload} <- Store.get(ref) do
      attrs = Mapper.movie_attrs(tmdb_id, payload, nil)
      movie = apply_update(movie, Map.take(attrs, @movie_fields))
      _ = ExternalIds.put(:imdb, movie, attrs.imdb_id)
      Library.broadcast_entities_changed([movie.id])
      Log.info(:pipeline, "re-projected movie #{movie.id} from the TMDB store")
      :ok
    else
      nil -> :ok
    end
  end

  def reapply({tmdb_id, :tv_series} = ref) do
    with %TVSeries{} = series <- ExternalIds.find_by_external_id(:tv_series, to_string(tmdb_id)),
         %{payload: payload} <- Store.get(ref) do
      attrs = Mapper.tv_attrs(tmdb_id, payload)
      series = apply_update(series, Map.take(attrs, @series_fields))
      _ = ExternalIds.put(:imdb, series, attrs.imdb_id)
      today = Date.utc_today()

      series.id
      |> Seasons.list_for_tv_series()
      |> Enum.each(&reapply_season(&1, tmdb_id, payload, today))

      Library.broadcast_entities_changed([series.id])
      Log.info(:pipeline, "re-projected series #{series.id} from the TMDB store")
      :ok
    else
      nil -> :ok
    end
  end

  defp reapply_season(season, tmdb_id, title_payload, today) do
    case season_payload(tmdb_id, season, title_payload, today) do
      nil ->
        :ok

      season_payload ->
        _season = apply_episode_list(season, Mapper.episode_list(season_payload))

        season.id
        |> Episodes.list_for_season()
        |> Enum.each(&reapply_episode(&1, season_payload))
    end
  end

  # The stored season; first contact for an open one the store lacks;
  # nothing for a closed one it never held.
  defp season_payload(tmdb_id, season, title_payload, today) do
    case Store.get_season(tmdb_id, season.season_number) do
      %{payload: payload} ->
        payload

      nil ->
        if open_season?(season, title_payload, today),
          do: first_contact_season(tmdb_id, season.season_number)
    end
  end

  defp first_contact_season(tmdb_id, season_number) do
    case Store.ensure_season(tmdb_id, season_number) do
      {:ok, %{payload: payload}} ->
        payload

      {:error, reason} ->
        Log.warning(
          :pipeline,
          "could not first-contact season S#{season_number} of tv tmdb:#{tmdb_id}: #{inspect(reason)}"
        )

        nil
    end
  end

  # An episode the stored season does not name — a file numbered beyond
  # what TMDB knows — keeps what it has.
  defp reapply_episode(episode, season_payload) do
    if Enum.any?(season_payload["episodes"] || [], &(&1["episode_number"] == episode.episode_number)) do
      attrs =
        season_payload
        |> Mapper.episode_attrs(episode.episode_number)
        |> Map.take(@episode_fields)

      case Episodes.update(episode, attrs) do
        {:ok, _episode} ->
          :ok

        {:error, changeset} ->
          Log.warning(
            :pipeline,
            "episode #{episode.id} refused its TMDB details: #{inspect(changeset.errors)}"
          )
      end
    end

    :ok
  end

  # Mirrors `TMDB.Schedule.open_season?/3` on the library's own list: the
  # series' latest numbered season, or one naming an undated or future
  # episode, may still change.
  defp open_season?(season, title_payload, today) do
    latest =
      title_payload
      |> Map.get("seasons", [])
      |> List.wrap()
      |> Enum.map(& &1["season_number"])
      |> Enum.reject(&(&1 in [nil, 0]))
      |> Enum.max(fn -> nil end)

    season.season_number == latest or
      Enum.any?(season.episode_list || [], fn entry ->
        is_nil(entry.air_date) or Date.after?(entry.air_date, today)
      end)
  end

  defp apply_update(record, attrs) do
    case Containers.update(record, attrs) do
      {:ok, updated} ->
        updated

      {:error, changeset} ->
        Log.warning(:pipeline, "#{record.id} refused its TMDB fields: #{inspect(changeset.errors)}")
        record
    end
  end

  defp apply_episode_list(season, entries) do
    case Seasons.update_episode_list(season, entries) do
      {:ok, updated} ->
        updated

      {:error, changeset} ->
        Log.warning(
          :pipeline,
          "season #{season.id} refused its episode list: #{inspect(changeset.errors)}"
        )

        season
    end
  end
end
