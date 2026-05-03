defmodule MediaCentarr.ReleaseTracking do
  use Boundary, deps: [MediaCentarr.TMDB, MediaCentarr.Library]

  @moduledoc """
  Bounded context for tracking upcoming movie and TV releases via TMDB.

  Fully isolated from the Library context — owns its own tables, images,
  and TMDB extraction logic.
  """

  import Ecto.Query
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Repo
  alias MediaCentarr.ReleaseTracking.{Item, Release, Event, Extractor, Helpers, ImageStore}
  alias MediaCentarr.Topics
  alias MediaCentarr.TMDB.Client

  @doc "Subscribe the caller to release tracking update events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.release_tracking_updates())
  end

  # --- Items ---

  def track_item(attrs) do
    Repo.insert(Item.create_changeset(attrs))
  end

  def track_item!(attrs) do
    Repo.insert!(Item.create_changeset(attrs))
  end

  def ignore_item(%Item{} = item) do
    Repo.update(Item.update_changeset(item, %{status: :ignored}))
  end

  def watch_item(%Item{} = item) do
    Repo.update(Item.update_changeset(item, %{status: :watching}))
  end

  def update_item(%Item{} = item, attrs) do
    Repo.update(Item.update_changeset(item, attrs))
  end

  @doc """
  Updates per-item auto-grab preferences and broadcasts `:releases_updated`
  so subscribed LiveViews refresh.

  `attrs` may include `:auto_grab_mode`, `:min_quality`, `:max_quality`,
  `:quality_4k_patience_hours`, `:prefer_season_packs`. Validation lives
  on `Item.auto_grab_changeset/2`.
  """
  def update_auto_grab(%Item{} = item, attrs) do
    case Repo.update(Item.auto_grab_changeset(item, attrs)) do
      {:ok, updated} ->
        broadcast_releases_updated([updated.id])
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def get_item(id), do: Repo.get(Item, id)

  def get_item_by_tmdb(tmdb_id, media_type) do
    Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type)
  end

  def delete_item(%Item{} = item) do
    item_id = item.id
    tmdb_id = to_string(item.tmdb_id)
    tmdb_type = tmdb_type_for(item.media_type)
    result = Repo.delete(item)
    broadcast_releases_updated([item_id])
    broadcast_item_removed(tmdb_id, tmdb_type)
    result
  end

  defp broadcast_item_removed(tmdb_id, tmdb_type) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.release_tracking_updates(),
      {:item_removed, tmdb_id, tmdb_type}
    )
  end

  @doc """
  Finds the highest season/episode pair for a TV series in the library.
  Returns `{season_number, episode_number}`, or `{0, 0}` if the series has
  no episodes (or `library_entity_id` is nil). Used by the Upcoming page
  to compute "next up" markers against the user's library state.
  """
  @spec find_last_library_episode(library_entity_id :: Ecto.UUID.t() | nil) ::
          {non_neg_integer(), non_neg_integer()}
  defdelegate find_last_library_episode(library_entity_id), to: Helpers

  def list_watching_items do
    Repo.all(
      from(i in Item, where: i.status == :watching, order_by: [asc: i.name], preload: [:releases])
    )
  end

  def list_all_items do
    Repo.all(from(i in Item, order_by: [asc: i.name], preload: [:releases]))
  end

  def tracking_status({tmdb_id, media_type}) do
    case Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type) do
      nil -> nil
      item -> item.status
    end
  end

  # --- Suggestions ---

  @active_tv_statuses [:returning, :in_production, :planned]

  @doc """
  Returns untracked library TV series with active TMDB status and external IDs.
  Used to populate the suggestions section of the Track New Show modal.
  """
  def suggest_trackable_items do
    tracked_tv_tmdb_ids =
      from(i in Item,
        where: i.media_type == :tv_series,
        select: fragment("CAST(? AS TEXT)", i.tmdb_id)
      )

    Repo.all(
      from(tv in MediaCentarr.Library.TVSeries,
        join: ext in MediaCentarr.Library.ExternalId,
        on: ext.tv_series_id == tv.id and ext.source == "tmdb",
        left_join: img in MediaCentarr.Library.Image,
        on: img.tv_series_id == tv.id and img.role == "poster",
        where:
          (tv.status in ^@active_tv_statuses or is_nil(tv.status)) and
            ext.external_id not in subquery(tracked_tv_tmdb_ids),
        select: %{
          tv_series_id: tv.id,
          tmdb_id: ext.external_id,
          name: tv.name,
          media_type: :tv_series,
          poster_url: img.content_url
        }
      )
    )
  end

  # --- Search ---

  @doc """
  Searches TMDB for both movies and TV shows in parallel. Returns a unified
  list of results with media_type, tmdb_id, name, year, poster_path, and
  an already_tracked flag.
  """
  def search_tmdb(query) do
    [movie_outcome, tv_outcome] =
      [:movie, :tv]
      |> Task.async_stream(
        fn
          :movie -> {:movie, Client.search_movie(query)}
          :tv -> {:tv, Client.search_tv(query)}
        end,
        timeout: 10_000,
        on_timeout: :kill_task,
        ordered: true,
        max_concurrency: 2
      )
      |> Enum.map(fn
        {:ok, outcome} -> outcome
        {:exit, _reason} -> :error
      end)

    movie_results =
      case movie_outcome do
        {:movie, {:ok, results}} -> Enum.map(results, &normalize_movie_result/1)
        _ -> []
      end

    tv_results =
      case tv_outcome do
        {:tv, {:ok, results}} -> Enum.map(results, &normalize_tv_result/1)
        _ -> []
      end

    tracked_tmdb_ids =
      from(i in Item, select: {i.tmdb_id, i.media_type})
      |> Repo.all()
      |> MapSet.new()

    Enum.map(movie_results ++ tv_results, fn result ->
      tracked = MapSet.member?(tracked_tmdb_ids, {result.tmdb_id, result.media_type})
      Map.put(result, :already_tracked, tracked)
    end)
  end

  defp normalize_movie_result(tmdb) do
    %{
      tmdb_id: tmdb["id"],
      media_type: :movie,
      name: tmdb["title"],
      year: extract_year(tmdb["release_date"]),
      poster_path: tmdb["poster_path"]
    }
  end

  defp normalize_tv_result(tmdb) do
    %{
      tmdb_id: tmdb["id"],
      media_type: :tv_series,
      name: tmdb["name"],
      year: extract_year(tmdb["first_air_date"]),
      poster_path: tmdb["poster_path"]
    }
  end

  defp extract_year(nil), do: nil
  defp extract_year(""), do: nil
  defp extract_year(<<year::binary-size(4), _::binary>>), do: year

  # --- Track from search ---

  @doc """
  Creates a tracking item from a search result. Used by the Track New Show modal.

  Accepts a result map (%{tmdb_id, media_type, name, poster_path}) and options:
  - For TV: %{start_season: n, start_episode: n} to set tracking offset
  - For movies: %{} (no options needed)
  """
  def track_from_search(result, opts \\ %{}) do
    start_season = Map.get(opts, :start_season, 0)
    start_episode = Map.get(opts, :start_episode, 0)

    case do_track_from_search(result, start_season, start_episode) do
      {:ok, item} ->
        broadcast_releases_updated([item.id])
        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_track_from_search(%{media_type: :tv_series} = result, start_season, start_episode) do
    case Client.get_tv(result.tmdb_id) do
      {:ok, response} ->
        all_releases =
          Helpers.fetch_tv_releases(result.tmdb_id, start_season, start_episode, response)

        # "All upcoming" (0,0) = only future episodes. Custom scope = include released too.
        releases =
          if start_season == 0 && start_episode == 0 do
            Enum.reject(all_releases, & &1[:released])
          else
            all_releases
          end

        {:ok, item} =
          track_item(%{
            tmdb_id: result.tmdb_id,
            media_type: :tv_series,
            name: response["name"] || result.name,
            source: :manual,
            last_refreshed_at: DateTime.utc_now(),
            last_library_season: start_season,
            last_library_episode: start_episode
          })

        persist_releases(item, releases)
        create_began_tracking_event(item)
        schedule_image_downloads(item, result.tmdb_id, response)

        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_track_from_search(%{media_type: :movie} = result, _start_season, _start_episode) do
    case Client.get_movie(result.tmdb_id) do
      {:ok, response} ->
        {:ok, item} =
          track_item(%{
            tmdb_id: result.tmdb_id,
            media_type: :movie,
            name: response["title"] || result.name,
            source: :manual,
            last_refreshed_at: DateTime.utc_now()
          })

        releases = Extractor.extract_movie_release_dates(response)
        persist_movie_releases(item, releases)

        create_began_tracking_event(item)
        schedule_image_downloads(item, result.tmdb_id, response)

        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_movie_releases(item, releases) do
    today = Date.utc_today()

    Enum.each(releases, fn release ->
      released = release.air_date != nil && Date.compare(release.air_date, today) != :gt

      create_release!(%{
        item_id: item.id,
        air_date: release.air_date,
        title: release.title,
        release_type: release.release_type,
        released: released
      })
    end)
  end

  defp broadcast_releases_updated(item_ids) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.release_tracking_updates(),
      {:releases_updated, item_ids}
    )
  end

  defp persist_releases(item, releases) do
    Enum.each(releases, fn release ->
      create_release!(%{
        item_id: item.id,
        air_date: release[:air_date],
        title: release[:title],
        season_number: release[:season_number],
        episode_number: release[:episode_number],
        released: release[:released] || false
      })
    end)

    mark_in_library_releases(item)
  end

  defp create_began_tracking_event(item) do
    create_event!(%{
      item_id: item.id,
      item_name: item.name,
      event_type: :began_tracking,
      description: "Now tracking #{item.name}"
    })
  end

  defp schedule_image_downloads(item, tmdb_id, response) do
    poster_path = Extractor.extract_poster_path(response)
    backdrop_path = response["backdrop_path"]

    if poster_path || backdrop_path do
      Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
        attrs = %{}

        attrs =
          case ImageStore.download_poster(tmdb_id, poster_path) do
            {:ok, path} when is_binary(path) -> Map.put(attrs, :poster_path, path)
            _ -> attrs
          end

        attrs =
          case ImageStore.download_backdrop(tmdb_id, backdrop_path) do
            {:ok, path} when is_binary(path) -> Map.put(attrs, :backdrop_path, path)
            _ -> attrs
          end

        if attrs != %{} do
          update_item(item, attrs)
          broadcast_releases_updated([item.id])
        end
      end)
    end
  end

  # --- Releases ---

  def create_release(attrs) do
    Repo.insert(Release.create_changeset(attrs))
  end

  def create_release!(attrs) do
    Repo.insert!(Release.create_changeset(attrs))
  end

  # Releases are always deleted and recreated (never updated individually).
  # Use delete_releases_for_item + create_release! instead.

  # 24-hour window for keeping recently-completed releases visible on the
  # "Now Available" section so the user sees the success transition instead
  # of the row vanishing when the watcher imports the file.
  @recent_completion_hours 24

  def list_releases do
    cutoff = recently_completed_cutoff()

    all =
      Repo.all(
        from(r in Release,
          join: i in assoc(r, :item),
          where:
            i.status == :watching and
              (r.in_library == false or
                 (r.in_library == true and not is_nil(r.in_library_at) and
                    r.in_library_at >= ^cutoff)),
          order_by: [asc: r.air_date],
          preload: [:item]
        )
      )

    upcoming = Enum.reject(all, & &1.released)
    released = Enum.filter(all, & &1.released)

    %{upcoming: upcoming, released: released}
  end

  defp recently_completed_cutoff do
    DateTime.add(DateTime.utc_now(:second), -@recent_completion_hours * 3600, :second)
  end

  @doc "Dismiss a single release by deleting it."
  def dismiss_release(release_id) do
    case Repo.get(Release, release_id) do
      nil ->
        {:error, :not_found}

      release ->
        result = Repo.delete(release)
        broadcast_releases_updated([release.item_id])
        result
    end
  end

  def list_releases_for_item(item_id) do
    Repo.all(from(r in Release, where: r.item_id == ^item_id, order_by: [asc: r.air_date]))
  end

  def delete_releases_for_item(item_id) do
    Repo.delete_all(from(r in Release, where: r.item_id == ^item_id))
  end

  # --- Events ---

  def create_event(attrs) do
    Repo.insert(Event.create_changeset(attrs))
  end

  def create_event!(attrs) do
    Repo.insert!(Event.create_changeset(attrs))
  end

  def list_recent_events(limit \\ 20) do
    Repo.all(
      from(e in Event,
        order_by: [{:desc, e.inserted_at}, {:desc, fragment("rowid")}],
        limit: ^limit
      )
    )
  end

  # --- Bulk operations ---

  @doc """
  Mark releases as in_library for a given item.

  TV series: episodes at or before last_library_season/episode are in the library.
  Movies: all releases with `released: true` are marked (the library entity existing
  means the collection is tracked, and released movies are available).
  """
  def mark_in_library_releases(%Item{media_type: :tv_series} = item) do
    season = item.last_library_season || 0
    episode = item.last_library_episode || 0

    if season > 0 do
      now = DateTime.utc_now(:second)

      # `where: r.in_library == false` makes the update idempotent — re-marking
      # an already-in-library row would otherwise re-bump in_library_at on
      # every refresh cycle, breaking the 24h linger window.
      {count, _} =
        Repo.update_all(
          from(r in Release,
            where: r.item_id == ^item.id and r.in_library == false,
            where:
              r.season_number < ^season or
                (r.season_number == ^season and r.episode_number <= ^episode)
          ),
          set: [in_library: true, in_library_at: now]
        )

      if count > 0, do: broadcast_releases_updated([item.id])
    end
  end

  def mark_in_library_releases(%Item{media_type: :movie} = item) do
    now = DateTime.utc_now(:second)
    acquirable_types = acquirable_release_types()

    {count, _} =
      Repo.update_all(
        from(r in Release,
          where:
            r.item_id == ^item.id and r.released == true and r.in_library == false and
              (is_nil(r.release_type) or r.release_type in ^acquirable_types)
        ),
        set: [in_library: true, in_library_at: now]
      )

    if count > 0, do: broadcast_releases_updated([item.id])
  end

  @doc """
  Whether a `release_type` represents a release the user can acquire on their
  own (digital file, physical disc, or back-compat untyped row). Theatrical
  releases are informational only — the date the movie hits theaters has
  nothing to do with downloads.

  Single source of truth so `mark_in_library_releases/1`, the bulk-queue
  orchestration, and any UI code that needs to classify a release type all
  agree.
  """
  @spec acquirable_release_type?(String.t() | nil) :: boolean()
  def acquirable_release_type?(nil), do: true
  def acquirable_release_type?(type) when is_binary(type), do: type in acquirable_release_types()

  defp acquirable_release_types, do: ["digital", "physical"]

  @doc """
  Returns the item's identifying info plus a deduped list of release coordinates
  (`%{season_number: …, episode_number: …}`) for releases that are released,
  not in the library, and of an acquirable type.

  `tmdb_type` is the TMDB-standard string (`"tv"`, `"movie"`) — what Acquisition's
  Grab table and QueryBuilder both consume. This is *not* a stringified media_type
  enum (which would yield `"tv_series"` and break the QueryBuilder downstream).

  Used by `Acquisition.enqueue_all_pending_for_item/1` to bulk-arm grabs for
  a tracked item with one click. Movie items collapse digital + physical rows
  to a single `{nil, nil}` coordinate since they share an Acquisition grab key.
  """
  @spec list_pending_acquirable_releases_for_item(item_id :: String.t()) ::
          {:ok,
           %{
             tmdb_id: String.t(),
             tmdb_type: String.t(),
             name: String.t(),
             pending_releases: [
               %{season_number: integer() | nil, episode_number: integer() | nil}
             ]
           }}
          | {:error, :not_found}
  def list_pending_acquirable_releases_for_item(item_id) do
    case Repo.get(Item, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        pending =
          Repo.all(
            from(r in Release,
              where: r.item_id == ^item.id and r.released == true and r.in_library == false,
              order_by: [asc: r.season_number, asc: r.episode_number]
            )
          )
          |> Enum.filter(&acquirable_release_type?(&1.release_type))
          |> Enum.map(&%{season_number: &1.season_number, episode_number: &1.episode_number})
          |> Enum.uniq()

        {:ok,
         %{
           tmdb_id: to_string(item.tmdb_id),
           tmdb_type: tmdb_type_for(item.media_type),
           name: item.name,
           pending_releases: pending
         }}
    end
  end

  @doc """
  Translates a tracking-item `media_type` atom to the TMDB-standard
  string consumed by `MediaCentarr.Acquisition.Grab.tmdb_type` and
  `MediaCentarr.Acquisition.QueryBuilder.build/1`.

  Inverse of the Ecto-stringified form (`"tv_series"`), which would
  break QueryBuilder downstream — every auto-grab caller that hands
  TV item structs to Acquisition MUST run them through this translator.
  """
  @spec tmdb_type_for(:tv_series | :movie) :: String.t()
  def tmdb_type_for(:tv_series), do: "tv"
  def tmdb_type_for(:movie), do: "movie"

  @doc """
  Resolves the best available logo URL for a tracking item.

  Prefers the paired Library entity's logo (most authoritative — it's the same
  asset that drives the rest of the library); falls back to the tracking
  item's own `logo_path` (fetched directly from TMDB by the refresher for
  shows not yet imported); returns `nil` if neither is available.

  `library_logos` is the map returned by
  `MediaCentarr.Library.logo_urls_for_entities/1`, batched by the caller so
  a single query covers many items.

  Single source of truth for "what logo should this card show?" — both
  `upcoming_live` and `list_releases_between/3` route through here so the
  precedence rule lives in exactly one place.
  """
  @spec logo_url_for_item(%Item{}, %{Ecto.UUID.t() => String.t()}) :: String.t() | nil
  def logo_url_for_item(%Item{} = item, library_logos) do
    cond do
      item.library_entity_id && Map.get(library_logos, item.library_entity_id) ->
        Map.get(library_logos, item.library_entity_id)

      is_binary(item.logo_path) ->
        "/media-images/#{item.logo_path}"

      true ->
        nil
    end
  end

  @doc """
  List tracked releases with `air_date` between `from_date` and `to_date` (inclusive),
  for watching items only. Used by HomeLive's "Coming Up" digest.

  Returns plain maps in the shape:
    `%{item: %{id, entity_id, name, tmdb_id, media_type}, air_date, season_number, episode_number, status, backdrop_url, logo_url}`

  `entity_id` is the paired Library entity UUID (nil if the item is not yet
  in the library). `logo_url` is filled when the paired Library entity has a
  `logo` image, otherwise `nil`. `status` is `:scheduled` — callers may
  enrich this with live grab status from Acquisition.
  """
  @spec list_releases_between(Date.t(), Date.t(), keyword()) :: [map()]
  def list_releases_between(from_date, to_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, 8)

    releases =
      Repo.all(
        from(release in Release,
          join: item in assoc(release, :item),
          where:
            item.status == :watching and
              not is_nil(release.air_date) and
              release.air_date >= ^from_date and
              release.air_date <= ^to_date,
          order_by: [asc: release.air_date, asc: release.season_number, asc: release.episode_number],
          limit: ^limit,
          preload: [item: item]
        )
      )

    logo_urls =
      releases
      |> Enum.flat_map(fn r ->
        if r.item.library_entity_id, do: [{r.item.media_type, r.item.library_entity_id}], else: []
      end)
      |> MediaCentarr.Library.logo_urls_for_entities()

    Enum.map(releases, fn release ->
      backdrop_url =
        if release.item.backdrop_path do
          "/media-images/#{release.item.backdrop_path}"
        end

      logo_url = logo_url_for_item(release.item, logo_urls)

      %{
        item: %{
          id: release.item.id,
          entity_id: release.item.library_entity_id,
          name: release.item.name,
          tmdb_id: release.item.tmdb_id,
          media_type: release.item.media_type
        },
        air_date: release.air_date,
        season_number: release.season_number,
        episode_number: release.episode_number,
        status: :scheduled,
        backdrop_url: backdrop_url,
        logo_url: logo_url
      }
    end)
  end

  def mark_past_releases_as_released do
    today = Date.utc_today()

    Repo.update_all(
      from(r in Release,
        where: not is_nil(r.air_date) and r.air_date <= ^today and r.released == false
      ),
      set: [released: true]
    )
  end
end
