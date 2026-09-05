defmodule MediaCentaur.Acquisition.Plans.AlternativesGapEvidenceTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.ViewModels.GapEvidence
  alias MediaCentaur.Acquisition.Targeting

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    on_exit(fn ->
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, config)
    end)

    :ok
  end

  defp release(title, guid, attrs) do
    Map.merge(
      %{
        "title" => title,
        "guid" => guid,
        "indexerId" => 1,
        "indexer" => "indexer-a",
        "seeders" => Map.get(attrs, :seeders, 10)
      },
      Map.new(Map.delete(attrs, :seeders), fn {key, value} -> {to_string(key), value} end)
    )
  end

  # A movie whose searches surface only unusable results: two releases of
  # a different picture (identity mismatch) and one bait-sized release
  # that carries the right name (red flag outranks the identity check,
  # mirroring the run's gate order). `other-1` comes back from both terms
  # to pin guid dedup.
  defp stub_rejected_movie do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/indexer"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/indexerstatus"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)

          results =
            case query do
              "Sample Movie 1990" ->
                [
                  release("Another.Picture.1990.1080p.WEB-DL.x264", "other-1", %{
                    seeders: 5,
                    size: 2_000_000_000
                  }),
                  release("Sample.Movie.1990.1080p.WEB-DL.x264", "bait-1", %{
                    seeders: 40,
                    size: 1_000_000
                  })
                ]

              "Sample Movie" ->
                [
                  release("Another.Picture.1990.1080p.WEB-DL.x264", "other-1", %{
                    seeders: 5,
                    size: 2_000_000_000
                  }),
                  release("Third.Thing.2001.1080p.WEB-DL.x264", "other-2", %{
                    seeders: 2,
                    size: 1_800_000_000
                  })
                ]

              _other ->
                []
            end

          Req.Test.json(conn, results)

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  defp create_gap_movie do
    {:ok, created} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 1990})
    {:ok, plan} = Plans.fetch(created.id)
    [unit] = Plans.units_for(plan.id)
    {plan, unit}
  end

  describe "gap_evidence/1 — movie" do
    test "classifies every rejected candidate with the run's gate order, deduped by guid" do
      stub_rejected_movie()
      {plan, unit} = create_gap_movie()

      assert unit.status == "unfound"
      assert Plans.Board.build(plan).gaps == ["Sample Movie"]

      evidence = Plans.Alternatives.gap_evidence(plan)

      assert [
               %GapEvidence.Search{term: "Sample Movie 1990", result_count: 2},
               %GapEvidence.Search{term: "Sample Movie", result_count: 2}
             ] = evidence.searches

      assert Enum.all?(evidence.searches, &(&1.searched_at != nil))

      assert evidence.raw_total == 3

      reasons = Map.new(evidence.rejected, &{&1.guid, &1.reason})
      assert reasons == %{"other-1" => :identity, "bait-1" => :red_flag, "other-2" => :identity}

      assert evidence.checked_at != nil
    end

    test "an exclusion the user made earlier is reported as :excluded" do
      stub_rejected_movie()
      {plan, unit} = create_gap_movie()

      {:ok, _plan} = Plans.exclude_release(unit.id, "other-1")
      {:ok, plan} = Plans.fetch(plan.id)

      evidence = Plans.Alternatives.gap_evidence(plan)
      assert %{reason: :excluded} = Enum.find(evidence.rejected, &(&1.guid == "other-1"))
    end

    test "zero raw results yields searched terms with empty rejection" do
      {plan, _unit} = create_gap_movie()

      evidence = Plans.Alternatives.gap_evidence(plan)

      assert Enum.map(evidence.searches, &{&1.term, &1.result_count}) == [
               {"Sample Movie 1990", 0},
               {"Sample Movie", 0}
             ]

      assert evidence.rejected == []
      assert evidence.raw_total == 0
    end

    test "a failed search leaves no record — evidence says so instead of guessing" do
      Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      {plan, unit} = create_gap_movie()
      assert unit.status == "unfound"

      evidence = Plans.Alternatives.gap_evidence(plan)
      assert evidence.searches == []
      assert evidence.checked_at == nil
    end
  end

  describe "gap_evidence/1 — TV aggregate" do
    test "counts raw candidates across the gap units' ladder terms without classifying" do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              if query == "Sample Show" do
                [release("Other.Series.S01.1080p.WEB-DL.x264", "tv-other", %{size: 4_000_000_000})]
              else
                []
              end

            Req.Test.json(conn, results)

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, created} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}])
      {:ok, plan} = Plans.fetch(created.id)

      evidence = Plans.Alternatives.gap_evidence(plan)

      assert Enum.map(evidence.searches, & &1.term) == [
               "Sample Show",
               "Sample Show Season 1",
               "Sample Show S01",
               "Sample Show S01E01",
               "Sample Show S01E02"
             ]

      assert evidence.raw_total == 1
      assert evidence.rejected == []
    end
  end

  describe "choose_rejected/2" do
    test "assigns an identity-rejected candidate — the deliberate matcher override" do
      stub_rejected_movie()
      {plan, unit} = create_gap_movie()

      assert {:ok, _plan} = Plans.Alternatives.choose_rejected(unit.id, "other-1")

      board = Plans.Board.build(elem(Plans.fetch(plan.id), 1))
      assert board.covered == 1
      assert [%{guid: "other-1"}] = board.releases
      assert board.gaps == []
    end

    test "refuses TV units — the override is movie-only" do
      {:ok, created} = Plans.create_series_plan(selection(), [{1, 1}])
      [unit | _rest] = Plans.units_for(created.id)

      assert {:error, :movie_only} = Plans.Alternatives.choose_rejected(unit.id, "any-guid")
    end

    test "refuses a guid the corpus does not know" do
      stub_rejected_movie()
      {_plan, unit} = create_gap_movie()

      assert {:error, :alternative_unavailable} =
               Plans.Alternatives.choose_rejected(unit.id, "no-such-guid")
    end
  end

  defp selection do
    %Targeting.Selection{
      tmdb_id: "246810",
      title: "Sample Show",
      tracked?: false,
      seasons: [
        %Targeting.Season{
          season_number: 1,
          episodes:
            for episode <- 1..2 do
              %Targeting.Episode{
                season_number: 1,
                episode_number: episode,
                label: "Episode #{episode}",
                aired?: true,
                in_library?: false
              }
            end
        }
      ]
    }
  end
end
