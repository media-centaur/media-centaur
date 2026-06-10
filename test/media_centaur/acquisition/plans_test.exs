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

  defp poison_searches_allow_grabs do
    Req.Test.stub(:prowlarr, fn conn ->
      case conn.method do
        "POST" -> Req.Test.json(conn, %{"approved" => true})
        method -> raise "indexer searched (#{method}) despite a fresh corpus"
      end
    end)
  end

  describe "the draft-plan lifecycle (ADR-055 Phase 3)" do
    test "create → autonomous solve → steer → approve → one composite pursuit" do
      stub_ladder_results()

      # ── Create: inline Oban runs the planning pass immediately. ──────
      assert {:ok, plan} =
               Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

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

      # ── Steer: "not this release" on the pack. The replan resolves
      # from the now-fresh corpus — zero further indexer searches. ──────
      poison_searches_allow_grabs()

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

    test "the swap picker: alternatives are listed from the corpus, suspicious flagged not hidden, choice reassigns" do
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
      # The bait was never auto-picked despite 999 seeders.
      assert Enum.all?(units, &(&1.assigned_guid == "pack-s1"))

      [first_unit | _rest] = units
      {:ok, alternatives} = Plans.alternatives_for(first_unit.id)

      # Clean candidate first; the bait visible but flagged and sorted last.
      assert [clean, evil] = alternatives
      assert clean.guid == "e1-uhd"
      refute clean.suspicious?
      assert clean.size_bytes == 2_400_000_000
      assert evil.guid == "e1-evil"
      assert evil.suspicious?

      # Deliberate choice reassigns exactly the units the choice covers.
      assert {:ok, _plan} = Plans.choose_release(first_unit.id, "e1-uhd")

      units = Plans.units_for(plan.id)
      chosen_unit = Enum.find(units, &(&1.episode_number == 1))
      assert chosen_unit.assigned_guid == "e1-uhd"
      assert chosen_unit.assigned_size_bytes == 2_400_000_000
      assert Enum.find(units, &(&1.episode_number == 2)).assigned_guid == "pack-s1"
      assert Enum.find(units, &(&1.episode_number == 3)).assigned_guid == "pack-s1"
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
  end
end
