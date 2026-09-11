defmodule MediaCentaur.Activities.Publisher do
  @moduledoc """
  Turns a person's acts elsewhere in the app into activities for their
  friends, while the matching sharing toggle is on:

  | Act | Source | Toggle | Activity |
  |---|---|---|---|
  | Finished a movie or an episode | `watch_history:events`, `{:watch_event_created, event}` | `share_watched` | `Activities.watched/2` |
  | Listed a title — its rung crossed onto List from below | `discovery:updates`, `{:title_intent_changed, %RungChanged{}}` | `share_watchlist` | `Activities.listing/1` |
  | Dropped a listed title below List | the same message, the other way | none | `Activities.withdraw/3` |

  A listing follows the rung transition (ADR-067): `RungChanged` carries
  both ends, so crossing onto List is read off the message, and only the
  crossing publishes — moving up the ladder afterwards is not another
  listing. Dropping below List (Off, or Ignored) withdraws the listing
  **whether or not the toggle is still on**: a statement that is no
  longer true is withdrawn; the toggle governs what gets said, not what
  stands. With no listing to withdraw the drop is a no-op.

  A GenServer only because it holds the two subscriptions; it keeps no
  state. Each message is handled on a supervised task (ADR-049), so a
  burst of completions never queues behind one another's lookups.

  A watched activity needs the title's TMDB identity, resolved through
  the Library context's public reads: the movie's own external id, or
  the episode's series' — an entity without one, and every extra
  (`video_object`), is not shared. The title snapshot is the entity's
  name, date and description; poster and backdrop are left for the
  receiving install, which fetches artwork from the identity as it does
  for every activity. A listing's snapshot rides on the event.

  Listed under the application's `pubsub_listeners`, so not started
  under `:test`; tests start it by hand.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.Events.RungChanged
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Library.{Containers, Episodes, ExternalIds, Seasons}
  alias MediaCentaur.Settings.Preferences.{ShareWatched, ShareWatchlist}
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.WatchHistory

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    WatchHistory.subscribe()
    Discovery.subscribe()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:watch_event_created, %WatchHistory.Event{} = event}, state) do
    if ShareWatched.enabled?(), do: run(fn -> share_watched(event) end)
    {:noreply, state}
  end

  def handle_info({:title_intent_changed, %RungChanged{} = change}, state) do
    listed_before? = TitleIntent.rung_at_least?(change.previous_rung, :list)
    listed_now? = TitleIntent.rung_at_least?(change.rung, :list)

    cond do
      not listed_before? and listed_now? and ShareWatchlist.enabled?() ->
        run(fn -> share(:listing, Activities.listing(change.title)) end)

      listed_before? and not listed_now? ->
        run(fn -> withdraw_listing(change) end)

      true ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_call(:ping, _from, state), do: {:reply, :ok, state}

  @doc false
  # Test seam: returns once every message sent before the call has been
  # handled, so a test can drain the tasks those messages started.
  def __ping_for_test__, do: GenServer.call(__MODULE__, :ping)

  defp run(fun) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fun)
    :ok
  end

  defp share_watched(%WatchHistory.Event{} = event) do
    case watched_title(event) do
      {:ok, title, episode} -> share(:watched, Activities.watched(title, episode))
      :skip -> :ok
    end
  end

  defp share(kind, {:ok, activity}), do: Log.info(:social, "shared #{kind}: #{activity.title.name}")

  defp share(kind, {:error, reason}),
    do: Log.warning(:social, "could not share #{kind}: #{inspect(reason)}")

  defp withdraw_listing(%RungChanged{} = change) do
    case Activities.withdraw(:listing, change.tmdb_id, change.media_type) do
      {:ok, activity} -> Log.info(:social, "withdrew listing: #{activity.title.name}")
      :ok -> :ok
      {:error, reason} -> Log.warning(:social, "could not withdraw listing: #{inspect(reason)}")
    end
  end

  # The title a completion is about, with the episode for a series —
  # or `:skip` when the entity is gone or carries no TMDB identity.
  defp watched_title(%WatchHistory.Event{entity_type: :movie, movie_id: id}) when is_binary(id) do
    with {:ok, movie} <- Containers.fetch(:movie, id),
         {:ok, tmdb_id} <- tmdb_id(ExternalIds.tmdb_ids_for_movies([id])) do
      {:ok, snapshot(tmdb_id, :movie, movie), nil}
    else
      _absent -> :skip
    end
  end

  defp watched_title(%WatchHistory.Event{entity_type: :episode, episode_id: id}) when is_binary(id) do
    with {:ok, episode} <- Episodes.fetch(id),
         {:ok, season} <- Seasons.fetch(episode.season_id),
         {:ok, series} <- Containers.fetch(:tv_series, season.tv_series_id),
         {:ok, tmdb_id} <- tmdb_id(ExternalIds.tmdb_ids_for_tv_series([season.tv_series_id])) do
      {:ok, snapshot(tmdb_id, :tv_series, series),
       %Episode{
         season_number: season.season_number,
         episode_number: episode.episode_number,
         name: episode.name
       }}
    else
      _absent -> :skip
    end
  end

  defp watched_title(_extra_or_unlinked), do: :skip

  defp tmdb_id([{_owner_id, external_id}]) do
    case Integer.parse(external_id) do
      {tmdb_id, ""} when tmdb_id > 0 -> {:ok, tmdb_id}
      _other -> :error
    end
  end

  defp tmdb_id(_none), do: :error

  defp snapshot(tmdb_id, media_type, entity) do
    Title.new!(%{
      tmdb_id: tmdb_id,
      media_type: media_type,
      name: entity.name,
      year: year(entity.date_published),
      release_date: entity.date_published,
      overview: entity.description
    })
  end

  defp year(%Date{year: year}), do: Integer.to_string(year)
  defp year(_none), do: nil
end
