defmodule MediaCentaurWeb.Live.TitleDetailHost.FinishTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.Events.SessionEnded
  alias MediaCentaurWeb.Live.TitleDetailHost.Finish

  defp ended(entity_id, completed),
    do: %SessionEnded{entity_id: entity_id, completed: MapSet.new(completed)}

  describe "reaction/4 — a standalone movie" do
    test "opens a standalone movie the session completed" do
      assert Finish.reaction(ended("movie-1", [{:movie, "movie-1"}]), nil, true, nil) ==
               {:open, "movie-1"}
    end

    test "shows in place when the movie's own detail is open" do
      assert Finish.reaction(ended("movie-1", [{:movie, "movie-1"}]), "movie-1", true, nil) ==
               {:in_place, "movie-1"}
    end

    test "opens over another title's open detail" do
      assert Finish.reaction(ended("movie-1", [{:movie, "movie-1"}]), "movie-2", true, nil) ==
               {:open, "movie-1"}
    end

    test "ignores a session that completed nothing" do
      assert Finish.reaction(ended("movie-1", []), nil, true, nil) == :ignore
    end

    test "ignores extras" do
      assert Finish.reaction(ended("movie-1", [{:extra, "extra-1"}]), nil, true, nil) == :ignore
    end

    test "ignores everything with the preference off" do
      assert Finish.reaction(ended("movie-1", [{:movie, "movie-1"}]), nil, false, nil) == :ignore
    end
  end

  describe "reaction/4 — a movie in a collection" do
    test "finishes the movie itself, not the collection" do
      assert Finish.reaction(ended("collection-1", [{:movie, "movie-1"}]), nil, true, nil) ==
               {:open, "movie-1"}
    end

    test "shows in place when the collection is open on that movie" do
      assert Finish.reaction(ended("collection-1", [{:movie, "movie-1"}]), "movie-1", true, nil) ==
               {:in_place, "movie-1"}
    end

    test "opens on the movie when the collection is open on another member" do
      assert Finish.reaction(ended("collection-1", [{:movie, "movie-1"}]), "movie-2", true, nil) ==
               {:open, "movie-1"}
    end
  end

  describe "reaction/4 — a series" do
    test "finishes the show when the session completed TMDB's latest aired episode" do
      completed = [{:episode, "episode-9", 2, 9}, {:episode, "episode-10", 2, 10}]

      assert Finish.reaction(ended("series-1", completed), nil, true, {2, 10}) ==
               {:open, "series-1"}
    end

    test "shows in place on the show's open detail" do
      completed = [{:episode, "episode-10", 2, 10}]

      assert Finish.reaction(ended("series-1", completed), "series-1", true, {2, 10}) ==
               {:in_place, "series-1"}
    end

    test "ignores earlier episodes" do
      completed = [{:episode, "episode-9", 2, 9}]
      assert Finish.reaction(ended("series-1", completed), nil, true, {2, 10}) == :ignore
    end

    test "ignores the last episode the library holds when TMDB lists later ones" do
      completed = [{:episode, "episode-10", 1, 10}]
      assert Finish.reaction(ended("series-1", completed), nil, true, {4, 8}) == :ignore
    end

    test "ignores a show with no latest aired episode on record" do
      completed = [{:episode, "episode-10", 2, 10}]
      assert Finish.reaction(ended("series-1", completed), nil, true, nil) == :ignore
    end

    test "ignores a show with the preference off" do
      completed = [{:episode, "episode-10", 2, 10}]
      assert Finish.reaction(ended("series-1", completed), nil, false, {2, 10}) == :ignore
    end
  end

  describe "episodes?/1" do
    test "whether the session completed any episode — when the host reads the TMDB record" do
      assert Finish.episodes?(ended("series-1", [{:episode, "episode-1", 1, 1}]))
      refute Finish.episodes?(ended("movie-1", [{:movie, "movie-1"}]))
      refute Finish.episodes?(ended("series-1", []))
    end
  end

  describe "latest_aired_episode/1" do
    test "reads TMDB's last_episode_to_air as season and episode numbers" do
      payload = %{"last_episode_to_air" => %{"season_number" => 3, "episode_number" => 12}}
      assert Finish.latest_aired_episode(payload) == {3, 12}
    end

    test "nil when the payload has none" do
      assert Finish.latest_aired_episode(%{"last_episode_to_air" => nil}) == nil
      assert Finish.latest_aired_episode(%{}) == nil
    end
  end
end
