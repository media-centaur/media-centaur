defmodule MediaCentaurWeb.Live.TitleDetailHost.FinishTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.Events.SessionEnded
  alias MediaCentaurWeb.Live.TitleDetailHost.Finish

  defp ended(entity_id, completed),
    do: %SessionEnded{entity_id: entity_id, completed: MapSet.new(completed)}

  describe "reaction/3" do
    test "opens a standalone movie the session completed" do
      assert Finish.reaction(ended("movie-1", [{:movie, "movie-1"}]), nil, true) == {:open, "movie-1"}
    end

    test "shows in place when the movie's own detail is open" do
      assert Finish.reaction(ended("movie-1", [{:movie, "movie-1"}]), "movie-1", true) ==
               {:in_place, "movie-1"}
    end

    test "opens over another title's open detail" do
      assert Finish.reaction(ended("movie-1", [{:movie, "movie-1"}]), "movie-2", true) ==
               {:open, "movie-1"}
    end

    test "ignores a session that completed nothing" do
      assert Finish.reaction(ended("movie-1", []), nil, true) == :ignore
    end

    test "ignores a movie in a collection — the session's entity is the collection" do
      assert Finish.reaction(ended("collection-1", [{:movie, "movie-1"}]), nil, true) == :ignore
    end

    test "ignores episodes and extras" do
      assert Finish.reaction(ended("series-1", [{:episode, "episode-1"}]), nil, true) == :ignore
      assert Finish.reaction(ended("movie-1", [{:extra, "extra-1"}]), nil, true) == :ignore
    end

    test "ignores everything with the preference off" do
      assert Finish.reaction(ended("movie-1", [{:movie, "movie-1"}]), nil, false) == :ignore
    end
  end
end
