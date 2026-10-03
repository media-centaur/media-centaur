defmodule MediaCentaur.ReleaseTracking.MoviesAddedTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Watchlist
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Settings.Preferences.WatchlistAutoRemove

  describe "movies_added/1 with the preference on (the default)" do
    test "a listed movie leaves the watchlist when it arrives" do
      create_title_intent(%{tmdb_id: 4101, media_type: :movie, name: "Movie A", rung: :list})

      :ok = ReleaseTracking.movies_added([4101])

      assert Watchlist.rung(4101, :movie) == nil
    end

    test "a movie at a tracking rung leaves too: the arrival is what it waited for" do
      create_title_intent(%{tmdb_id: 4102, media_type: :movie, name: "Movie B", rung: :follow})
      create_title_intent(%{tmdb_id: 4103, media_type: :movie, name: "Movie C", rung: :grab})

      :ok = ReleaseTracking.movies_added([4102, 4103])

      assert Watchlist.rung(4102, :movie) == nil
      assert Watchlist.rung(4103, :movie) == nil
    end

    test "an ignored movie is not on the watchlist and keeps its record" do
      create_title_intent(%{tmdb_id: 4104, media_type: :movie, name: "Movie D", rung: :ignored})

      :ok = ReleaseTracking.movies_added([4104])

      assert Watchlist.rung(4104, :movie) == :ignored
    end

    test "a series sharing the number is a different title and stays" do
      create_title_intent(%{tmdb_id: 4105, media_type: :tv_series, name: "Sample Show", rung: :list})

      :ok = ReleaseTracking.movies_added([4105])

      assert Watchlist.rung(4105, :tv_series) == :list
    end

    test "a movie nobody listed is nothing to do" do
      assert :ok = ReleaseTracking.movies_added([4106])
      assert Watchlist.rung(4106, :movie) == nil
    end
  end

  describe "movies_added/1 with the preference off" do
    test "the watchlist is left alone" do
      WatchlistAutoRemove.set(false)
      create_title_intent(%{tmdb_id: 4201, media_type: :movie, name: "Movie E", rung: :list})

      :ok = ReleaseTracking.movies_added([4201])

      assert Watchlist.rung(4201, :movie) == :list
    end
  end

  test "the preference is on until someone turns it off" do
    assert WatchlistAutoRemove.enabled?()
  end
end
