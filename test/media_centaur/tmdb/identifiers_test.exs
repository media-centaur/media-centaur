defmodule MediaCentaur.TMDB.IdentifiersTest do
  use MediaCentaur.Case, async: true

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
end
