defmodule MediaCentarr.Library.ExternalIdsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.ExternalIds
  alias MediaCentarr.Repo

  import MediaCentarr.TestFactory

  describe "put/3" do
    test "inserts a new ExternalId row keyed off the container struct" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      assert {:ok, row} = ExternalIds.put(:tmdb, movie, "12345")
      assert row.source == "tmdb"
      assert row.external_id == "12345"
      assert row.movie_id == movie.id
    end

    test "writes a tv_series ExternalId pointing at the tv series owner" do
      tv = create_tv_series(%{name: "Sample Show"})

      assert {:ok, row} = ExternalIds.put(:tmdb, tv, "1396")
      assert row.tv_series_id == tv.id
      assert row.movie_id == nil
    end

    test "writes a movie_series ExternalId with source :tmdb_collection" do
      series = create_movie_series(%{name: "Sample Collection"})

      assert {:ok, row} = ExternalIds.put(:tmdb_collection, series, "263")
      assert row.source == "tmdb_collection"
      assert row.movie_series_id == series.id
    end

    test "writes an imdb ExternalId" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      assert {:ok, row} = ExternalIds.put(:imdb, movie, "tt0000001")
      assert row.source == "imdb"
      assert row.external_id == "tt0000001"
      assert row.movie_id == movie.id
    end

    test "no-ops when nil id is passed" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      assert :ok = ExternalIds.put(:imdb, movie, nil)
      reloaded = Repo.preload(movie, :external_ids)
      assert reloaded.external_ids == []
    end

    test "returns the existing row when the same (source, external_id) already points at the owner" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      {:ok, first} = ExternalIds.put(:tmdb, movie, "550")
      {:ok, second} = ExternalIds.put(:tmdb, movie, "550")

      assert first.id == second.id

      reloaded = Repo.preload(movie, :external_ids)
      assert length(reloaded.external_ids) == 1
    end

    test "returns {:error, changeset} (not raise) when (source, external_id) already attaches to a different movie" do
      # Regression: partial unique indexes must be `(source, external_id)`
      # with the FK only in the WHERE clause, AND the changeset must
      # declare a matching `unique_constraint([:source, :external_id])`
      # so the DB constraint surfaces as `{:error, changeset}` rather
      # than `Ecto.ConstraintError`. This is what makes race-loss
      # recovery in `Library.Inbound` reachable.
      first = create_standalone_movie(%{name: "Sample Movie One"})
      second = create_standalone_movie(%{name: "Sample Movie Two"})

      {:ok, _} = ExternalIds.put(:tmdb, first, "12345")

      assert {:error, %Ecto.Changeset{} = changeset} = ExternalIds.put(:tmdb, second, "12345")
      assert {_field, {_msg, opts}} = hd(changeset.errors)
      assert opts[:constraint] == :unique
    end

    test "returns {:error, changeset} on cross-tv-series conflict" do
      first = create_tv_series(%{name: "Sample Show One"})
      second = create_tv_series(%{name: "Sample Show Two"})

      {:ok, _} = ExternalIds.put(:tmdb, first, "1396")

      assert {:error, %Ecto.Changeset{} = changeset} = ExternalIds.put(:tmdb, second, "1396")
      assert {_field, {_msg, opts}} = hd(changeset.errors)
      assert opts[:constraint] == :unique
    end
  end

  describe "get/2" do
    test "returns the external_id for the given source on a preloaded record" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      {:ok, _} = ExternalIds.put(:tmdb, movie, "550")

      reloaded = Library.get_movie_with_associations!(movie.id)
      assert ExternalIds.get(reloaded, :tmdb) == "550"
    end

    test "returns nil when the source is absent" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      reloaded = Library.get_movie_with_associations!(movie.id)

      assert ExternalIds.get(reloaded, :tmdb) == nil
      assert ExternalIds.get(reloaded, :imdb) == nil
    end

    test "distinguishes :tmdb from :imdb on the same record" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      {:ok, _} = ExternalIds.put(:tmdb, movie, "550")
      {:ok, _} = ExternalIds.put(:imdb, movie, "tt0000001")

      reloaded = Library.get_movie_with_associations!(movie.id)
      assert ExternalIds.get(reloaded, :tmdb) == "550"
      assert ExternalIds.get(reloaded, :imdb) == "tt0000001"
    end
  end

  describe "find_owner/2" do
    test "finds a Movie owning a TMDB id" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      {:ok, _} = ExternalIds.put(:tmdb, movie, "550")

      assert {:ok, :movie, found} = ExternalIds.find_owner(:tmdb, "550")
      assert found.id == movie.id
    end

    test "finds a TVSeries owning a TMDB id" do
      tv = create_tv_series(%{name: "Sample Show"})
      {:ok, _} = ExternalIds.put(:tmdb, tv, "1396")

      assert {:ok, :tv_series, found} = ExternalIds.find_owner(:tmdb, "1396")
      assert found.id == tv.id
    end

    test "finds a MovieSeries owning a tmdb_collection id" do
      series = create_movie_series(%{name: "Sample Collection"})
      {:ok, _} = ExternalIds.put(:tmdb_collection, series, "263")

      assert {:ok, :movie_series, found} = ExternalIds.find_owner(:tmdb_collection, "263")
      assert found.id == series.id
    end

    test "returns :not_found when no row matches" do
      assert :not_found = ExternalIds.find_owner(:tmdb, "999999")
    end

    test "TMDB id 12345 can simultaneously belong to a Movie and a TVSeries" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      tv = create_tv_series(%{name: "Sample Show"})

      assert {:ok, _} = ExternalIds.put(:tmdb, movie, "12345")
      assert {:ok, _} = ExternalIds.put(:tmdb, tv, "12345")

      # find_owner only finds *one* — caller specifies which by trying
      # in order (mirrors the Inbound resolution flow).
      assert {:ok, type, _} = ExternalIds.find_owner(:tmdb, "12345")
      assert type in [:movie, :tv_series]
    end
  end
end
