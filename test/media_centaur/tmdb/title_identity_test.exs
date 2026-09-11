defmodule MediaCentaur.TMDB.TitleIdentityTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TMDB.TitleIdentity

  defp identity(attrs) do
    TitleIdentity.new(Map.merge(%{tmdb_type: :movie, tmdb_id: 1, title: "Sample Film"}, attrs))
  end

  describe "new/1" do
    test "normalises the tmdb id to a string and the library's tv vocabulary to :tv" do
      assert %TitleIdentity{tmdb_id: "1234", tmdb_type: :tv} =
               TitleIdentity.new(%{tmdb_type: :tv_series, tmdb_id: 1234, title: "Sample Show"})
    end

    test "defaults origin_country to a list rather than nil" do
      assert identity(%{}).origin_country == []
    end

    test "refuses an identity with no tmdb identity to speak of" do
      assert_raise ArgumentError, fn ->
        struct!(TitleIdentity, title: "Sample Film")
      end
    end
  end

  describe "from_payload/2" do
    test "reads a movie's imdb id from the top level and its year from the release date" do
      payload = %{
        "id" => 663_875,
        "title" => "Sample Film",
        "original_title" => "Beispielfilm",
        "imdb_id" => "tt11887594",
        "release_date" => "2020-02-21"
      }

      assert %TitleIdentity{
               tmdb_type: :movie,
               tmdb_id: "663875",
               title: "Sample Film",
               original_title: "Beispielfilm",
               imdb_id: "tt11887594",
               year: 2020
             } = TitleIdentity.from_payload(:movie, payload)
    end

    test "reads a series' ids from the appended external_ids block" do
      payload = %{
        "id" => 246_810,
        "name" => "Sample Show",
        "first_air_date" => "2023-09-29",
        "origin_country" => ["JP"],
        "external_ids" => %{"imdb_id" => "tt22248376", "tvdb_id" => 424_536}
      }

      assert %TitleIdentity{
               tmdb_type: :tv,
               tmdb_id: "246810",
               imdb_id: "tt22248376",
               tvdb_id: "424536",
               year: 2023,
               origin_country: ["JP"]
             } = TitleIdentity.from_payload(:tv, payload)
    end

    test "a blank or absent date leaves the year nil rather than failing" do
      assert TitleIdentity.from_payload(:movie, %{"id" => 1, "title" => "A"}).year == nil

      assert TitleIdentity.from_payload(:movie, %{"id" => 1, "title" => "A", "release_date" => ""}).year ==
               nil
    end
  end

  describe "compare/2" do
    test "one agreeing id settles identity" do
      left = identity(%{imdb_id: "tt111"})
      right = identity(%{imdb_id: "tt111"})

      assert TitleIdentity.compare(left, right) == :match
    end

    test "comparable ids that all disagree is a rejection" do
      # The live defect: two different films both named Filipiñana.
      wanted = identity(%{tmdb_id: 663_875, imdb_id: "tt11887594"})
      declared = identity(%{tmdb_id: 1_417_935, imdb_id: "tt38268539"})

      assert TitleIdentity.compare(wanted, declared) == :mismatch
    end

    test "one agreeing id outweighs another disagreeing" do
      # Indexers mis-tag a single field far more often than they get
      # every field wrong.
      left = identity(%{tmdb_id: 500, imdb_id: "tt111"})
      right = identity(%{tmdb_id: 999, imdb_id: "tt111"})

      assert TitleIdentity.compare(left, right) == :match
    end

    test "nothing comparable is :unknown, not a rejection" do
      # The common torrent-indexer case: the result declares no ids at
      # all, so the name heuristic has to decide. Silence is not a no.
      assert TitleIdentity.compare(identity(%{imdb_id: "tt1"}), %{}) == :unknown
      assert TitleIdentity.compare(identity(%{imdb_id: "tt1"}), %{tvdb_id: "9"}) == :unknown
    end

    test "compares against a sparse declared side, not only a full identity" do
      wanted = identity(%{tmdb_id: 663_875, imdb_id: "tt11887594"})

      assert TitleIdentity.compare(wanted, %{imdb_id: "tt38268539"}) == :mismatch
      assert TitleIdentity.compare(wanted, %{imdb_id: "tt11887594"}) == :match
    end

    test "reads an indexer's integer id spelling" do
      # Prowlarr sends ids as integers, with 0 meaning absent.
      wanted = identity(%{tmdb_id: 663_875})

      assert TitleIdentity.compare(wanted, %{"tmdb_id" => 663_875}) == :match
      assert TitleIdentity.compare(wanted, %{"tmdb_id" => 0}) == :unknown
    end

    test "a missing identity is unknown rather than a crash" do
      assert TitleIdentity.compare(nil, identity(%{})) == :unknown
      assert TitleIdentity.compare(identity(%{}), nil) == :unknown
    end
  end
end
