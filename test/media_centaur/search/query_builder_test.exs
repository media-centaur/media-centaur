defmodule MediaCentaur.Search.QueryBuilderTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.{Criteria, QueryBuilder}

  describe "build/1 — movie" do
    test "includes year and type=:movie when year is present" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :movie,
        title: "Sample Movie",
        year: 2010
      }

      assert [{query, opts}] = QueryBuilder.build(criteria)
      assert query == "Sample Movie 2010"
      assert Keyword.get(opts, :type) == :movie
      assert Keyword.get(opts, :year) == 2010
    end

    test "omits year and year-opt when year is nil" do
      criteria = %Criteria{
        type: :tmdb,
        tmdb_type: :movie,
        title: "Sample Movie",
        year: nil
      }

      assert [{query, opts}] = QueryBuilder.build(criteria)
      assert query == "Sample Movie"
      assert Keyword.get(opts, :type) == :movie
      refute Keyword.has_key?(opts, :year)
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

      assert [{"Sample Show S03E04", opts}] = QueryBuilder.build(criteria)
      assert Keyword.get(opts, :type) == :tv
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

      assert [
               {"Sample Show Season 3", primary_opts},
               {"Sample Show S03", fallback_opts}
             ] = QueryBuilder.build(criteria)

      assert Keyword.get(primary_opts, :type) == :tv
      assert Keyword.get(fallback_opts, :type) == :tv
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
end
