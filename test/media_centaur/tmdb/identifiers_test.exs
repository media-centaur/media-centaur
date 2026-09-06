defmodule MediaCentaur.TMDB.IdentifiersTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.TMDB.Identifiers

  describe "from_payload/2" do
    test "reads a movie's IMDb id from the top level of the detail payload" do
      assert %{imdb_id: "tt0133093", tvdb_id: nil} =
               Identifiers.from_payload(:movie, %{"imdb_id" => "tt0133093"})
    end

    test "reads a series' ids from the appended external_ids block" do
      payload = %{"external_ids" => %{"imdb_id" => "tt0903747", "tvdb_id" => 81_189}}

      assert %{imdb_id: "tt0903747", tvdb_id: "81189"} = Identifiers.from_payload(:tv, payload)
    end

    test "an absent, blank or zero id reads as no id at all" do
      assert %{imdb_id: nil, tvdb_id: nil} = Identifiers.from_payload(:movie, %{})
      assert %{imdb_id: nil, tvdb_id: nil} = Identifiers.from_payload(:movie, %{"imdb_id" => ""})
      assert %{imdb_id: nil, tvdb_id: nil} = Identifiers.from_payload(:tv, %{})

      assert %{imdb_id: nil, tvdb_id: nil} =
               Identifiers.from_payload(:tv, %{"external_ids" => %{"imdb_id" => nil, "tvdb_id" => 0}})
    end
  end

  describe "fetch/3" do
    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client(self())
      :ok
    end

    test "fetches a movie's IMDb id from TMDB" do
      MediaCentaur.TmdbStubs.stub_get_movie("603", %{"title" => "Sample Movie", "imdb_id" => "tt0133093"})

      assert %{imdb_id: "tt0133093", tvdb_id: nil} = Identifiers.fetch(:movie, "603")
    end

    test "fetches a series' ids from TMDB" do
      MediaCentaur.TmdbStubs.stub_get_tv("1396", %{
        "name" => "Sample Show",
        "external_ids" => %{"imdb_id" => "tt0903747", "tvdb_id" => 81_189}
      })

      assert %{imdb_id: "tt0903747", tvdb_id: "81189"} = Identifiers.fetch(:tv, "1396")
    end

    test "an unreachable TMDB yields no ids rather than an error — identity is optional" do
      MediaCentaur.TmdbStubs.stub_tmdb_error("/movie/603")

      assert %{imdb_id: nil, tvdb_id: nil} = Identifiers.fetch(:movie, "603")
    end
  end
end
