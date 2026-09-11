defmodule MediaCentaur.Activities.PublisherTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory

  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Activities.Publisher
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Settings.Preferences.{ShareWatched, ShareWatchlist}
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.Topics
  alias MediaCentaur.WatchHistory

  # Not a pubsub listener under :test — started by hand, on this test's
  # sandbox connection.
  setup do
    TmdbStubs.setup_tmdb_client()
    {:ok, pid} = Publisher.start_link([])
    Ecto.Adapters.SQL.Sandbox.allow(MediaCentaur.Repo, self(), pid)
    :ok
  end

  defp completed(attrs) do
    event = create_watch_event(attrs)
    Topics.publish(Topics.watch_history_events(), {:watch_event_created, event})
    settle()
    Activities.list_sent()
  end

  # The publisher handles the message, then its task does the work.
  defp settle do
    :ok = Publisher.__ping_for_test__()
    await_supervised_tasks()
  end

  defp movie_with_tmdb(tmdb_id) do
    movie =
      create_movie(%{name: "Sample Movie", date_published: ~D[1999-03-31], description: "An overview."})

    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: Integer.to_string(tmdb_id)})
    movie
  end

  defp episode_with_tmdb(tmdb_id) do
    series = create_tv_series(%{name: "Sample Show"})

    create_external_id(%{
      tv_series_id: series.id,
      source: "tmdb",
      external_id: Integer.to_string(tmdb_id)
    })

    season = create_season(%{tv_series_id: series.id, season_number: 2})
    create_episode(%{season_id: season.id, episode_number: 5, name: "The Fifth"})
  end

  describe "watched" do
    test "off by default: a completion publishes nothing" do
      movie = movie_with_tmdb(603)
      assert completed(%{entity_type: :movie, movie_id: movie.id}) == []
    end

    test "a finished movie becomes a watched activity with the library's snapshot" do
      ShareWatched.set(true)
      movie = movie_with_tmdb(603)

      assert [%Activity{kind: :watched, tmdb_id: 603, media_type: :movie, episode: nil} = activity] =
               completed(%{entity_type: :movie, movie_id: movie.id})

      assert activity.title.name == "Sample Movie"
      assert activity.title.year == "1999"
      assert activity.title.overview == "An overview."
    end

    test "a finished episode names the series and the episode" do
      ShareWatched.set(true)
      episode = episode_with_tmdb(1399)

      assert [%Activity{kind: :watched, tmdb_id: 1399, media_type: :tv_series} = activity] =
               completed(%{entity_type: :episode, episode_id: episode.id, title: "Sample Show S02E05"})

      assert activity.title.name == "Sample Show"
      assert %Episode{season_number: 2, episode_number: 5, name: "The Fifth"} = activity.episode
    end

    test "an entity without a TMDB identity, and an extra, are not shared" do
      ShareWatched.set(true)
      movie = create_movie(%{name: "Untitled"})
      assert completed(%{entity_type: :movie, movie_id: movie.id}) == []
      assert completed(%{entity_type: :video_object, title: "Bonus"}) == []
    end
  end

  describe "listing" do
    defp show,
      do: MediaCentaur.TMDB.Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})

    defp listings, do: Enum.filter(Activities.list_sent(), &(&1.kind == :listing))

    test "off by default: listing a title publishes nothing" do
      {:ok, _intent} = ReleaseTracking.set_rung(show(), :list)
      settle()
      assert Activities.list_sent() == []
    end

    test "a title reaching List becomes a listing with the intent's snapshot" do
      ShareWatchlist.set(true)
      {:ok, _intent} = ReleaseTracking.set_rung(show(), :list)
      settle()

      assert [%Activity{kind: :listing, tmdb_id: 1399, media_type: :tv_series} = activity] = listings()
      assert activity.title.name == "Sample Show"
      assert activity.raw_event["kind"] == 32_163
    end

    test "leaving Ignored for the list is a listing; moving up the ladder is not another" do
      ShareWatchlist.set(true)
      {:ok, _intent} = ReleaseTracking.set_rung(show(), :ignored)
      settle()
      assert listings() == []

      {:ok, _intent} = ReleaseTracking.set_rung(show(), :list)
      settle()
      assert [%Activity{kind: :listing} = first] = listings()

      # `:follow` needs a calendar, which is a TMDB fetch; `:ask` stays local.
      {:ok, _intent} = ReleaseTracking.set_rung(show(), :ask)
      settle()
      assert [%Activity{id: id}] = listings()
      assert id == first.id
      assert Activity.event_created_at(hd(listings())) == Activity.event_created_at(first)
    end

    test "dropping below List withdraws the listing — with the toggle on or off" do
      ShareWatchlist.set(true)
      {:ok, _intent} = ReleaseTracking.set_rung(show(), :list)
      settle()
      assert [%Activity{kind: :listing}] = listings()

      # The statement is no longer true; a switched-off toggle does not
      # keep it standing on friends' shelves.
      ShareWatchlist.set(false)
      {:ok, nil} = ReleaseTracking.set_rung(show(), :off)
      settle()
      assert listings() == []
      assert [%MediaCentaur.Nostr.Event{kind: 5}] = Activities.own_events()

      ShareWatchlist.set(true)
      {:ok, _intent} = ReleaseTracking.set_rung(show(), :list)
      settle()
      assert [%Activity{kind: :listing}] = listings()

      {:ok, _intent} = ReleaseTracking.set_rung(show(), :ignored)
      settle()
      assert listings() == []
    end

    test "a title never listed dropping to Off publishes nothing" do
      ShareWatchlist.set(true)
      {:ok, nil} = ReleaseTracking.set_rung(show(), :off)
      settle()
      assert Activities.own_events() == []
    end
  end

  test "the recorder's own message shape is what the publisher reads" do
    # `WatchHistory.Recorder` publishes `{:watch_event_created, event}`;
    # this pins the coupling so a rename there fails here.
    assert Topics.watch_history_events() == "watch_history:events"
    assert function_exported?(WatchHistory, :subscribe, 0)
  end
end
