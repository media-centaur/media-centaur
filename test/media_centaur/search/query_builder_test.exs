defmodule MediaCentaur.Search.QueryBuilderTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.{Criteria, QueryBuilder}

  describe "build/1 — movie" do
    test "year query first, year-less second (release years drift)" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :movie,
        title: "Sample Movie",
        year: 2010
      }

      assert [{query, opts}, {broader_query, broader_opts}] = QueryBuilder.build(criteria)
      assert query == "Sample Movie 2010"
      assert broader_query == "Sample Movie"
      # Both are searched — they are alternate phrasings of one want, not
      # a ladder — so both carry the same category scope.
      assert Keyword.get(opts, :categories) == :movie
      assert Keyword.get(broader_opts, :categories) == :movie
    end

    test "never sends a year opt — the search endpoint has no such parameter" do
      criteria = %Criteria{type: :tmdb, tmdb_type: :movie, title: "Sample Movie", year: 2010}

      assert Enum.all?(QueryBuilder.build(criteria), fn {_query, opts} ->
               not Keyword.has_key?(opts, :year)
             end)
    end

    test "strips apostrophes from constructed queries (scene names carry none)" do
      movie = %Criteria{type: :tmdb, tmdb_type: :movie, title: "Sample's Movie", year: nil}
      assert [{"Samples Movie", _opts}] = QueryBuilder.build(movie)

      episode = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Sample's Show",
        season_number: 1,
        episode_number: 2
      }

      assert [{"Samples Show S01E02", _opts}] = QueryBuilder.build(episode)
    end

    test "omits the year token from the query when the year is nil" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :movie,
        title: "Sample Movie",
        year: nil
      }

      assert [{query, opts}] = QueryBuilder.build(criteria)
      assert query == "Sample Movie"
      assert Keyword.get(opts, :categories) == :movie
    end
  end

  describe "build/1 — TV episode" do
    test "emits a single 'Title SxxExx' query — no season-pack fallback" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Sample Show",
        season_number: 3,
        episode_number: 4
      }

      assert [{"Sample Show S03E04", _opts}] = QueryBuilder.build(criteria)
    end

    test "pads single-digit season and episode" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Show",
        season_number: 1,
        episode_number: 1
      }

      assert [{"Show S01E01", _}] = QueryBuilder.build(criteria)
    end

    test "preserves double-digit season and episode without padding" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Show",
        season_number: 12,
        episode_number: 23
      }

      assert [{"Show S12E23", _}] = QueryBuilder.build(criteria)
    end

    test "does not include year on TV queries (release titles do not carry it)" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Sample Show",
        year: 2022,
        season_number: 3,
        episode_number: 4
      }

      assert [{_, opts}] = QueryBuilder.build(criteria)
      refute Keyword.has_key?(opts, :year)
    end
  end

  describe "build/1 — TV season pack (no episode)" do
    test "primary 'Title Season N', fallback 'Title SXX'" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Sample Show",
        season_number: 3,
        episode_number: nil
      }

      assert [{"Sample Show Season 3", _primary_opts}, {"Sample Show S03", _fallback_opts}] =
               QueryBuilder.build(criteria)
    end
  end

  describe "build/1 — cour-aware (later-run residual)" do
    # The first-run `Season N` query is wrong for a later cour — it
    # surfaces the first-run pack the coverage guard already refused.
    # When the criteria carry a later run, emit run-shaped queries.
    @later_run %{index: 1, first_ep: {1, 29}, last_ep: {1, 38}, date_span: nil}

    test "a later-run season residual emits cour queries, not the first-run Season N" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Sample Show",
        season_number: 1,
        episode_number: nil,
        run: @later_run
      }

      queries = Enum.map(QueryBuilder.build(criteria), &elem(&1, 0))

      assert "Sample Show 29-38" in queries
      assert "Sample Show 2nd Season" in queries
      refute "Sample Show Season 1" in queries
      refute "Sample Show S01" in queries
    end

    test "a later-run episode residual keeps its precise SxxExx query alongside cour queries" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Sample Show",
        season_number: 1,
        episode_number: 29,
        run: @later_run
      }

      queries = Enum.map(QueryBuilder.build(criteria), &elem(&1, 0))

      assert "Sample Show 29-38" in queries
      assert "Sample Show S01E29" in queries
    end

    test "a first-run (index 0) residual is unchanged — regression guard" do
      first_run = %{index: 0, first_ep: {1, 1}, last_ep: {1, 16}, date_span: nil}

      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :tv,
        title: "Sample Show",
        season_number: 1,
        episode_number: nil,
        run: first_run
      }

      assert [{"Sample Show Season 1", _}, {"Sample Show S01", _}] = QueryBuilder.build(criteria)
    end
  end

  describe "accented titles" do
    test "the outbound query carries the ASCII spelling the indexer indexes" do
      criteria = %Criteria{type: :tmdb, title: "Amélie", tmdb_type: :movie, year: 2001}

      assert QueryBuilder.build(criteria) == [
               {"Amelie 2001", [categories: :movie]},
               {"Amelie", [categories: :movie]}
             ]
    end

    test "a series' ladder queries are folded too" do
      criteria = %Criteria{type: :tmdb, title: "Filipiñana", tmdb_type: :tv, season_number: 1}

      assert QueryBuilder.build(criteria) == [
               {"Filipinana Season 1", [categories: :tv]},
               {"Filipinana S01", [categories: :tv]}
             ]
    end
  end

  describe "the original title as an alternate query" do
    test "a movie asks for its original title too, broadest last" do
      criteria = %Criteria{
        type: :tmdb,
        title: "Sample Movie",
        tmdb_type: :movie,
        year: 2001,
        original_title: "Le Fabuleux Destin de Sample"
      }

      assert QueryBuilder.build(criteria) == [
               {"Sample Movie 2001", [categories: :movie]},
               {"Sample Movie", [categories: :movie]},
               {"Le Fabuleux Destin de Sample", [categories: :movie]}
             ]
    end

    test "an original title that folds to the canonical one costs no extra search" do
      criteria = %Criteria{
        type: :tmdb,
        title: "Amélie",
        tmdb_type: :movie,
        year: 2001,
        original_title: "Amelie"
      }

      assert QueryBuilder.build(criteria) == [
               {"Amelie 2001", [categories: :movie]},
               {"Amelie", [categories: :movie]}
             ]
    end

    test "TV queries are unchanged — the ladder is a narrowing structure, not a list of phrasings" do
      criteria = %Criteria{
        type: :tmdb,
        title: "Sample Show",
        tmdb_type: :tv,
        season_number: 1,
        original_title: "Beispielserie"
      }

      assert QueryBuilder.build(criteria) == [
               {"Sample Show Season 1", [categories: :tv]},
               {"Sample Show S01", [categories: :tv]}
             ]
    end
  end
end
