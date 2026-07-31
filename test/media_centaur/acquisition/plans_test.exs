defmodule MediaCentaur.Acquisition.PlansTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Units}
  alias MediaCentaur.Acquisition.{Target, Targeting}
  alias MediaCentaur.Search.Prowlarr

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    config = :persistent_term.get({MediaCentaur.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentaur.Config, :config}, config)
    end)

    :ok
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
            for episode <- 1..3 do
              %Targeting.Episode{
                season_number: 1,
                episode_number: episode,
                label: "Episode #{episode}",
                aired?: true,
                in_library?: false
              }
            end
        },
        %Targeting.Season{
          season_number: 2,
          episodes: [
            %Targeting.Episode{
              season_number: 2,
              episode_number: 1,
              label: "Return",
              aired?: true,
              in_library?: false
            }
          ]
        }
      ]
    }
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
      Map.new(Map.delete(attrs, :seeders), fn {k, v} -> {to_string(k), v} end)
    )
  end

  defp stub_ladder_results do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)

          results =
            case query do
              "Sample Show Season 1" ->
                [release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})]

              "Sample Show S01E01" ->
                [release("Sample.Show.S01E01.2160p.WEB-DL.x265", "e1-uhd", %{seeders: 8})]

              _other ->
                []
            end

          Req.Test.json(conn, results)

        {"POST", "/api/v1/search"} ->
          Req.Test.json(conn, %{"approved" => true})

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  # The exclusion replan legitimately descends to the episode rung for
  # the newly-uncovered units — those terms were never searched in the
  # first pass (the pack covered them), so they aren't fresh. The
  # broad rungs MUST still come from the corpus: a series/season
  # re-search here would be the consult-first regression this guards.
  defp poison_broad_searches_allow_episode_descent do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", _path} ->
          Req.Test.json(conn, %{"approved" => true})

        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)

          if !(query =~ ~r/S\d{2}E\d{2}$/) do
            raise "broad rung searched (#{query}) despite a fresh corpus"
          end

          results =
            if query == "Sample Show S01E01" do
              [release("Sample.Show.S01E01.2160p.WEB-DL.x265", "e1-uhd", %{seeders: 8})]
            else
              []
            end

          Req.Test.json(conn, results)

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  # Movie whose only real releases sit below the quality floor (the
  # Magician-2005 shape): 720p, DVD, and one with no resolution token.
  defp stub_below_floor_movie do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)

          results =
            if query == "Sample Movie 2005" do
              [
                release("Sample.Movie.2005.720p.WEBRip.x264", "bf-720p", %{
                  seeders: 9,
                  size: 1_400_000_000
                }),
                release("Sample.Movie.2005.DVDRip.x264", "bf-dvd", %{
                  seeders: 4,
                  size: 700_000_000
                }),
                release("Sample.Movie.2005.AMZN.WEB-DL.DDP2.0.H.264", "bf-unlabeled", %{
                  seeders: 2,
                  size: 1_000_000_000
                })
              ]
            else
              []
            end

          Req.Test.json(conn, results)

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  describe "below-floor movie offers on the board" do
    test "board_for surfaces the below-floor offer instead of a bare gap" do
      stub_below_floor_movie()

      {:ok, created} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      {:ok, plan} = Plans.get(created.id)
      assert plan.status == "ready"

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"

      board = Plans.board_for(plan)

      assert [offer] = board.below_floor
      assert offer.unit_id == unit.id
      assert offer.unit_label == "Sample Movie"
      assert offer.count == 3

      # The offer row owns the unit — it is not also a bare "not
      # available" gap.
      assert board.gaps == []
    end

    test "the candidates are choosable through the swap picker, with display-quality labels" do
      stub_below_floor_movie()

      {:ok, created} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      assert [unit] = Plans.units_for(created.id)

      {:ok, alternatives} = Plans.alternatives_for(unit.id)

      assert Enum.map(alternatives, &{&1.guid, &1.quality}) == [
               {"bf-720p", "720p"},
               {"bf-dvd", "DVD"},
               {"bf-unlabeled", nil}
             ]

      # Grabbing one is a deliberate user pick — the floor does not
      # apply, and the assignment carries the display quality.
      assert {:ok, _plan} = Plans.choose_release(unit.id, "bf-720p")

      assert [grabbed] = Plans.units_for(created.id)
      assert grabbed.status == "found"
      assert grabbed.assigned_guid == "bf-720p"
      assert grabbed.assigned_quality == "720p"

      {:ok, reloaded} = Plans.get(created.id)
      assert Plans.board_for(reloaded).below_floor == []
    end
  end

  describe "the draft-plan lifecycle (ADR-055 Phase 3)" do
    test "create → autonomous solve → steer → approve → one composite pursuit" do
      stub_ladder_results()

      # ── Create: inline Oban runs the planning pass immediately. ──────
      assert {:ok, plan} =
               Plans.create_series_plan(
                 %{selection() | origin_country: ["US"]},
                 [{1, 1}, {1, 2}, {1, 3}, {2, 1}]
               )

      {:ok, plan} = Plans.get(plan.id)
      assert plan.status == "ready"

      units = Plans.units_for(plan.id)
      assert length(units) == 4

      # Coverage first: the season pack covers all of S1 (the 4K single
      # only covers one unit), so all three S1 units share the pack.
      s1_units = Enum.filter(units, &(&1.season_number == 1))
      assert Enum.all?(s1_units, &(&1.status == "found"))
      assert Enum.all?(s1_units, &(&1.assigned_guid == "pack-s1"))
      assert Enum.all?(s1_units, &(&1.assigned_scope == "Season 1 pack"))

      # Nothing covers S2E01 — a reported gap, never a pursuit leaf.
      [s2_unit] = Enum.filter(units, &(&1.season_number == 2))
      assert s2_unit.status == "unfound"

      # ── Steer: "not this release" on the pack. The replan re-reads
      # the fresh corpus for the broad rungs and descends live only to
      # the episode terms the first pass never needed. ──────────────────
      poison_broad_searches_allow_episode_descent()

      [first_s1 | _] = s1_units
      assert {:ok, _plan} = Plans.exclude_release(first_s1.id, "pack-s1")

      {:ok, plan} = Plans.get(plan.id)
      assert plan.status == "ready"

      units = Plans.units_for(plan.id)

      # Exclusions are plan-wide: the pack is gone everywhere; only the
      # 4K single remains, covering exactly its episode.
      assert Enum.find(units, &(&1.episode_number == 1 and &1.season_number == 1)).assigned_guid ==
               "e1-uhd"

      assert Enum.count(units, &(&1.status == "unfound")) == 3

      # ── Approve: found units become ONE composite pursuit. ───────────
      assert {:ok, committed} = Plans.approve(plan)
      assert committed.status == "committed"
      assert committed.pursuit_id

      pursuit = Repo.get!(Pursuit, committed.pursuit_id)
      assert pursuit.recipe_type == "tmdb"
      assert pursuit.tmdb_id == "246810"
      assert pursuit.title == "Sample Show"
      # Origin countries cross the plan → pursuit boundary so the
      # auto-grab matcher keeps accepting origin-tagged releases.
      assert pursuit.origin_country == ["US"]

      # Only the found unit crossed the search→pursuit boundary.
      assert [unit] = Units.for_pursuit(pursuit.id)
      assert unit.season_number == 1
      assert unit.episode_number == 1
      assert "e1-uhd" in unit.tried_release_guids

      target = Repo.get!(Target, unit.current_target_id)
      assert target.status == "acquired"
      assert target.prowlarr_guid == "e1-uhd"
      assert [covered] = Units.covered_by(target.id)
      assert covered.id == unit.id
    end

    test "board_for surfaces a fit-gated pack as one offer covering every unfound unit it would bring" do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              if query == "Sample Show Season 1" do
                [
                  release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{
                    seeders: 30,
                    size: 9_400_000_000
                  })
                ]
              else
                []
              end

            Req.Test.json(conn, results)

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      # 2 of season 1's 3 aired episodes — fit 0.67 < 0.75, so the only
      # cover (the season pack) is set aside as an offer, not grabbed.
      {:ok, created} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}])
      {:ok, plan} = Plans.get(created.id)
      assert plan.status == "ready"

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.status == "unfound"))

      board = Plans.board_for(plan)

      # One offer for the pack, not one per unfound unit.
      assert [offer] = board.offers
      assert offer.guid == "pack-s1"
      assert offer.scope_label == "Season 1 pack"
      assert offer.unit_label == "2 episodes"
      assert offer.size_bytes == 9_400_000_000

      # Grabbing the offer claims every unit the pack covers.
      assert {:ok, _plan} = Plans.choose_release(offer.unit_id, offer.guid)
      regrabbed = Plans.units_for(plan.id)
      assert Enum.all?(regrabbed, &(&1.assigned_guid == "pack-s1"))
      assert Plans.board_for(plan).offers == []
    end

    test "the swap picker: find-more live-fills the unit's terms consult-first, suspicious flagged not hidden, choice reassigns" do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              case query do
                "Sample Show Season 1" ->
                  [
                    release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{
                      seeders: 30,
                      size: 9_200_000_000
                    })
                  ]

                "Sample Show S01E01" ->
                  [
                    release("Sample.Show.S01E01.2160p.WEB-DL.x265", "e1-uhd", %{
                      seeders: 8,
                      size: 2_400_000_000
                    }),
                    # Bait: clean-looking name, implausible 4MB payload —
                    # the size floor must catch it without the exe token.
                    release("Sample.Show.S01E01.1080p.WEB-DL.x264", "e1-evil", %{
                      seeders: 999,
                      size: 4_000_000
                    })
                  ]

                _other ->
                  []
              end

            Req.Test.json(conn, results)

          {"POST", "/api/v1/search"} ->
            Req.Test.json(conn, %{"approved" => true})

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}])
      {:ok, plan} = Plans.get(plan.id)
      assert plan.status == "ready"

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.assigned_guid == "pack-s1"))

      [first_unit | _rest] = units

      # The descent stopped at the season rung, so the corpus holds
      # nothing deeper — the picker starts honest and empty.
      assert {:ok, []} = Plans.alternatives_for(first_unit.id)

      # "Find more" live-fills exactly the unit's never-searched terms.
      {:ok, alternatives} = Plans.search_alternatives(first_unit.id)

      # Clean candidate first; the bait visible but flagged and sorted
      # last — and it was never auto-picked despite 999 seeders.
      assert [clean, evil] = alternatives
      assert clean.guid == "e1-uhd"
      refute clean.suspicious?
      assert clean.size_bytes == 2_400_000_000
      assert evil.guid == "e1-evil"
      assert evil.suspicious?

      # Consult-first: a second find-more is served entirely from the
      # now-fresh corpus — zero indexer traffic.
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.method do
          "POST" -> Req.Test.json(conn, %{"approved" => true})
          method -> raise "indexer searched (#{method}) despite a fresh corpus"
        end
      end)

      assert {:ok, again} = Plans.search_alternatives(first_unit.id)
      assert Enum.map(again, & &1.guid) == Enum.map(alternatives, & &1.guid)

      # Deliberate choice reassigns exactly the units the choice covers.
      assert {:ok, _plan} = Plans.choose_release(first_unit.id, "e1-uhd")

      units = Plans.units_for(plan.id)
      chosen_unit = Enum.find(units, &(&1.episode_number == 1))
      assert chosen_unit.assigned_guid == "e1-uhd"
      assert chosen_unit.assigned_size_bytes == 2_400_000_000
      assert Enum.find(units, &(&1.episode_number == 2)).assigned_guid == "pack-s1"
      assert Enum.find(units, &(&1.episode_number == 3)).assigned_guid == "pack-s1"

      # The narrowing choice created containment overlap: the pack still
      # physically contains E01. The board flags it, CTA aimed at the pack.
      {:ok, plan} = Plans.get(plan.id)
      board = Plans.board_for(plan)
      assert [overlap] = board.overlaps
      assert overlap.exclude_guid == "pack-s1"
      assert overlap.description =~ "download twice"

      # Taking the CTA (exclude the container, re-solve) resolves the
      # overlap and keeps the user's narrower choice. The replan's episode
      # descent for E02/E03 legitimately goes live — allow it, empty.
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.method do
          "POST" -> Req.Test.json(conn, %{"approved" => true})
          _get -> Req.Test.json(conn, [])
        end
      end)

      assert {:ok, _plan} = Plans.exclude_release(overlap.exclude_unit_id, overlap.exclude_guid)

      {:ok, plan} = Plans.get(plan.id)
      assert Plans.board_for(plan).overlaps == []

      units = Plans.units_for(plan.id)
      assert Enum.find(units, &(&1.episode_number == 1)).assigned_guid == "e1-uhd"
      assert Enum.find(units, &(&1.episode_number == 2)).status == "unfound"
      assert Enum.find(units, &(&1.episode_number == 3)).status == "unfound"
    end

    test "approve grabs with the assigned indexer id even after the corpus candidate aged out" do
      test_pid = self()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              if query == "Sample Show S01E01" do
                [release("Sample.Show.S01E01.2160p.WEB-DL.x265", "e1-uhd", %{seeders: 8, indexerId: 7})]
              else
                []
              end

            Req.Test.json(conn, results)

          {"POST", "/api/v1/search"} ->
            {:ok, body, _conn} = Plug.Conn.read_body(conn)
            send(test_pid, {:grabbed, Jason.decode!(body)})
            Req.Test.json(conn, %{"approved" => true})

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}])
      {:ok, plan} = Plans.get(plan.id)

      unit = Enum.find(Plans.units_for(plan.id), &(&1.assigned_guid == "e1-uhd"))
      assert unit.assigned_indexer_id == 7

      # Retention prunes the candidate between ready and approve: rehydrate
      # must fall back to the unit's denormalized assignment, not nil.
      Repo.delete_all(MediaCentaur.Acquisition.Corpus.Candidate)

      assert {:ok, _committed} = Plans.approve(plan)

      assert_received {:grabbed, payload}
      assert payload["indexerId"] == 7
    end

    test "approve rejects a plan whose units an active pursuit already claims (overlap check)" do
      stub_ladder_results()

      {:ok, first_plan} = Plans.create_series_plan(selection(), [{1, 1}])
      {:ok, first_plan} = Plans.get(first_plan.id)
      {:ok, _committed} = Plans.approve(first_plan)

      {:ok, second_plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}])
      {:ok, second_plan} = Plans.get(second_plan.id)

      assert {:error, {:overlap, [{1, 1}]}} = Plans.approve(second_plan)
    end

    test "approve rejects against an auto-origin tmdb pursuit purely via unit identity" do
      # Pin for the ADR-055 retirement: the overlap check reads unit
      # identity only (no parent-level fallback), so a legacy
      # auto-grab-shaped pursuit must be visible through its unit.
      stub_ladder_results()

      {_pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: selection().tmdb_id,
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 1
        })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}])
      {:ok, plan} = Plans.get(plan.id)

      assert {:error, {:overlap, [{1, 1}]}} = Plans.approve(plan)
    end

    test "a plan with nothing found cannot be approved; discard closes it out" do
      # Default stub returns no results anywhere.
      {:ok, plan} = Plans.create_series_plan(selection(), [{2, 1}])
      {:ok, plan} = Plans.get(plan.id)
      assert plan.status == "ready"

      assert {:error, :nothing_to_grab} = Plans.approve(plan)

      assert {:ok, discarded} = Plans.discard(plan)
      assert discarded.status == "discarded"
    end

    test "movie plans: one unit, best acceptable pick" do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            Req.Test.json(conn, [
              release("Sample.Movie.2010.1080p.BluRay.x264", "movie-hd", %{seeders: 40}),
              release("Sample.Movie.2010.2160p.BluRay.x265", "movie-uhd", %{seeders: 4})
            ])

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2010})
      {:ok, plan} = Plans.get(plan.id)
      assert plan.status == "ready"

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      # User preference: the acceptable 4K wins over the better-seeded 1080p.
      assert unit.assigned_guid == "movie-uhd"
    end

    # Serves results keyed by exact query text — misses return empty,
    # so a query the indexer wouldn't match (apostrophe, wrong year)
    # stays a miss in the test exactly as it is live.
    defp stub_movie_searches(results_by_query) do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)
            Req.Test.json(conn, Map.get(results_by_query, query, []))

          _other ->
            Req.Test.json(conn, %{})
        end
      end)
    end

    test "movie plans: a drifted release year descends to the year-less term and still matches" do
      # TMDB says 2000 (theatrical); every release says 1999 (festival
      # premiere). The year term finds nothing; the year-less rung plus
      # the ±1 year tolerance land the release.
      stub_movie_searches(%{
        "Sample Movie" => [
          release("Sample.Movie.1999.1080p.BluRay.x264", "movie-1999", %{seeders: 15})
        ]
      })

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "778", title: "Sample Movie", year: 2000})
      {:ok, plan} = Plans.get(plan.id)
      assert plan.status == "ready"

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "movie-1999"
      assert unit.assigned_term == "Sample Movie"
    end

    test "movie plans: the search term carries no apostrophe (scene names carry none)" do
      stub_movie_searches(%{
        "Samples Movie 2010" => [
          release("Samples.Movie.2010.1080p.BluRay.x264", "movie-apos", %{seeders: 15})
        ]
      })

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "779", title: "Sample's Movie", year: 2010})
      {:ok, plan} = Plans.get(plan.id)
      assert plan.status == "ready"

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "movie-apos"
    end
  end
end
