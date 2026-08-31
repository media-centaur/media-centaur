defmodule MediaCentaur.Acquisition.Jobs.RunPlanTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Search.Prowlarr
  alias MediaCentaur.TmdbStubs

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, config)
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
      Map.new(Map.delete(attrs, :seeders), fn {key, value} -> {to_string(key), value} end)
    )
  end

  # Serves results_by_query and reports every live GET search back to
  # the test process — the descent assertions read the mailbox.
  defp stub_recording_searches(results_by_query) do
    test_pid = self()

    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
        # :unconfigured — not blind — so corpus recording behaves as before.
        {"GET", "/api/v1/indexer"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/indexerstatus"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)
          send(test_pid, {:searched, query})
          Req.Test.json(conn, Map.get(results_by_query, query, []))

        {"POST", "/api/v1/search"} ->
          Req.Test.json(conn, %{"approved" => true})

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  describe "residual-driven descent" do
    test "an acceptable complete-series pack stops the descent at the series rung" do
      stub_recording_searches(%{
        "Sample Show" => [
          release("Sample.Show.S01-02.COMPLETE.1080p.WEB-DL", "series-pack", %{seeders: 20})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.status == "found"))
      assert Enum.all?(units, &(&1.assigned_guid == "series-pack"))

      assert_received {:searched, "Sample Show"}
      refute_received {:searched, "Sample Show Season 1"}
      refute_received {:searched, "Sample Show S01"}
      refute_received {:searched, "Sample Show S01E01"}
      refute_received {:searched, "Sample Show S02E01"}
    end

    test "an origin-tagged pack satisfies the plan when the origin country matches (the Wilfred bug)" do
      stub_recording_searches(%{
        "Sample Show" => [
          release("Sample.Show.US.S01-02.COMPLETE.1080p.WEB-DL", "us-pack", %{seeders: 20})
        ]
      })

      selection = %{selection() | origin_country: ["US"]}
      {:ok, plan} = Plans.create_series_plan(selection, [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.status == "found"))
      assert Enum.all?(units, &(&1.assigned_guid == "us-pack"))
    end

    test "an origin-tagged pack is still rejected when the plan's origin country differs" do
      stub_recording_searches(%{
        "Sample Show" => [
          release("Sample.Show.US.S01-02.COMPLETE.1080p.WEB-DL", "us-pack", %{seeders: 20})
        ]
      })

      selection = %{selection() | origin_country: ["AU"]}
      {:ok, plan} = Plans.create_series_plan(selection, [{1, 1}])

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.status == "unfound"))
    end

    test "season packs satisfy the residual — the episode rung is never searched" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ],
        "Sample Show Season 2" => [
          release("Sample.Show.S02.COMPLETE.1080p.WEB-DL", "pack-s2", %{seeders: 30})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      units = Plans.units_for(plan.id)
      season_one_units = Enum.filter(units, &(&1.season_number == 1))
      assert Enum.all?(season_one_units, &(&1.assigned_guid == "pack-s1"))
      assert Enum.find(units, &(&1.season_number == 2)).assigned_guid == "pack-s2"

      assert_received {:searched, "Sample Show"}
      assert_received {:searched, "Sample Show Season 1"}
      assert_received {:searched, "Sample Show S01"}
      assert_received {:searched, "Sample Show Season 2"}
      assert_received {:searched, "Sample Show S02"}
      refute_received {:searched, "Sample Show S01E01"}
      refute_received {:searched, "Sample Show S01E02"}
      refute_received {:searched, "Sample Show S01E03"}
      refute_received {:searched, "Sample Show S02E01"}
    end

    test "episode terms are searched only for units the broader rungs left uncovered" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ],
        "Sample Show S02E01" => [
          release("Sample.Show.S02E01.1080p.WEB-DL", "single-s2e1", %{seeders: 12})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      units = Plans.units_for(plan.id)
      assert Enum.find(units, &(&1.season_number == 2)).assigned_guid == "single-s2e1"

      assert_received {:searched, "Sample Show S02E01"}
      refute_received {:searched, "Sample Show S01E01"}
      refute_received {:searched, "Sample Show S01E02"}
      refute_received {:searched, "Sample Show S01E03"}
    end

    test "one wanted episode never grabs the series pack — it descends to the single (the bug)" do
      stub_recording_searches(%{
        "Sample Show" => [
          release("Sample.Show.S01-02.COMPLETE.1080p.WEB-DL", "series-pack", %{seeders: 900})
        ],
        "Sample Show S01E01" => [
          release("Sample.Show.S01E01.1080p.WEB-DL", "single-s1e1", %{seeders: 5})
        ]
      })

      # Want just one of season 1's three aired episodes: fit 1/3 < 0.75,
      # so the series pack is set aside and the descent reaches the
      # episode rung that the old broad-first halt never ran.
      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}])

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "single-s1e1"

      assert_received {:searched, "Sample Show S01E01"}
    end

    test "one wanted episode with only an over-broad pack → unfound, pack offered (not grabbed)" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{
            seeders: 30,
            size: 9_000_000_000
          })
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}])

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"
      assert unit.assigned_guid == nil
      assert unit.offered_guid == "pack-s1"
      assert unit.offered_scope == "Season 1 pack"
      assert unit.offered_size_bytes == 9_000_000_000
    end

    test "a dry show walks the full ladder and reports every unit unfound" do
      stub_recording_searches(%{})

      {:ok, plan} = Plans.create_series_plan(selection(), [{2, 1}])

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"

      assert_received {:searched, "Sample Show"}
      assert_received {:searched, "Sample Show Season 2"}
      assert_received {:searched, "Sample Show S02"}
      assert_received {:searched, "Sample Show S02E01"}
    end

    test "an elevated per-unit floor keeps that unit in the residual past an acceptable pack" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ],
        "Sample Show S01E01" => [
          release("Sample.Show.S01E01.2160p.WEB-DL.x265", "e1-uhd", %{seeders: 8})
        ]
      })

      {:ok, plan} =
        Plans.create_tracking_plan(
          %{tmdb_id: "246810", tmdb_type: "tv", title: "Sample Show"},
          [
            %{season_number: 1, episode_number: 1, label: "S01E01", position: 0, min_quality: "uhd_4k"},
            %{season_number: 1, episode_number: 2, label: "S01E02", position: 1},
            %{season_number: 1, episode_number: 3, label: "S01E03", position: 2}
          ]
        )

      units = Plans.units_for(plan.id)
      assert Enum.find(units, &(&1.episode_number == 1)).assigned_guid == "e1-uhd"
      assert Enum.find(units, &(&1.episode_number == 2)).assigned_guid == "pack-s1"
      assert Enum.find(units, &(&1.episode_number == 3)).assigned_guid == "pack-s1"

      # Descent was per-unit: only the elevated unit's episode term ran.
      assert_received {:searched, "Sample Show S01E01"}
      refute_received {:searched, "Sample Show S01E02"}
      refute_received {:searched, "Sample Show S01E03"}
    end

    test "the descent narrates itself — full itinerary snapshots on acquisition:updates" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_updates())

      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ],
        "Sample Show Season 2" => [
          release("Sample.Show.S02.COMPLETE.1080p.WEB-DL", "pack-s2", %{seeders: 30})
        ]
      })

      {:ok, _plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      assert_received %PlanEvents.DescentStatus{wanted: 4} = series_active
      assert descent_states(series_active) == [series: :active, seasons: :pending, episodes: :pending]

      assert_received %PlanEvents.DescentStatus{} = seasons_active
      assert descent_states(seasons_active) == [series: :done, seasons: :active, episodes: :pending]

      assert_received %PlanEvents.DescentStatus{} = final
      assert descent_states(final) == [series: :done, seasons: :done, episodes: :skipped]
      assert Enum.find(final.stages, &(&1.id == :seasons)).residual_after == 0
      refute_received %PlanEvents.DescentStatus{}
    end
  end

  describe "movie source ladder (ADR-061)" do
    defp stub_same_tier_movie do
      stub_recording_searches(%{
        "Sample Movie 2005" => [
          release("Sample.Movie.2005.1080p.WEB-DL.DDP.5.1.H.264-GRP", "src-webdl", %{
            seeders: 90,
            size: 8_000_000_000
          }),
          release("Sample.Movie.2005.1080p.BluRay.x265", "src-encode", %{
            seeders: 90,
            size: 3_300_000_000
          }),
          release("Sample.Movie.2005.BluRay.1080p.REMUX.VC-1.DTS-HD.MA.5.1-GRP", "src-remux", %{
            seeders: 2,
            size: 28_000_000_000
          })
        ]
      })
    end

    test "equal-tier candidates pick by source fidelity, not list order or seeders" do
      stub_same_tier_movie()

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "src-remux"
    end

    test "the save-space preference picks the encode instead" do
      MediaCentaur.Settings.find_or_create_entry!(%{
        key: "auto_grab.size_preference",
        value: %{"value" => "space"}
      })

      stub_same_tier_movie()

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "src-encode"
    end
  end

  describe "movie below-floor releases" do
    # The Magician (2005) shape: genuine releases of the film exist, all
    # below the quality floor (≤720p or no resolution token). The unit
    # stays unfound — the floor holds — but carries the count so the
    # board can surface "lower quality available" instead of a bare gap.

    test "a movie whose only releases are lower quality lands unfound carrying the count" do
      stub_recording_searches(%{
        "Sample Movie 2005" => [
          release("Sample.Movie.2005.720p.WEBRip.x264", "bf-720p", %{
            seeders: 9,
            size: 1_400_000_000
          }),
          release("Sample.Movie.2005.DVDRip.x264", "bf-dvd", %{seeders: 4, size: 700_000_000}),
          release("Sample.Movie.2005.AMZN.WEB-DL.DDP2.0.H.264", "bf-unlabeled", %{
            seeders: 2,
            size: 1_000_000_000
          })
        ],
        # The year-less rung re-surfaces one of the same releases — the
        # count dedups by guid across rungs.
        "Sample Movie" => [
          release("Sample.Movie.2005.720p.WEBRip.x264", "bf-720p", %{
            seeders: 9,
            size: 1_400_000_000
          })
        ]
      })

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"
      assert unit.assigned_guid == nil
      assert unit.below_floor_count == 3
    end

    test "an acceptable release wins outright — no below-floor stamp" do
      stub_recording_searches(%{
        "Sample Movie 2005" => [
          release("Sample.Movie.2005.1080p.WEB-DL.H.264", "good-1080p", %{
            seeders: 12,
            size: 4_000_000_000
          }),
          release("Sample.Movie.2005.720p.WEBRip.x264", "bf-720p", %{
            seeders: 90,
            size: 1_400_000_000
          })
        ]
      })

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "good-1080p"
      assert unit.below_floor_count == 0
    end

    test "a dry movie search stays a bare unfound" do
      stub_recording_searches(%{})

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"
      assert unit.below_floor_count == 0
    end

    test "releases that fail identity or look like bait never count" do
      stub_recording_searches(%{
        "Sample Movie 2005" => [
          release("Different.Film.2005.720p.WEBRip.x264", "wrong-title", %{
            seeders: 5,
            size: 1_400_000_000
          }),
          release("Sample.Movie.2005.720p.WEBRip.x264.exe", "bait-exe", %{
            seeders: 5,
            size: 1_400_000_000
          }),
          release("Sample.Movie.2005.720p.WEBRip.x264-TINY", "bait-tiny", %{
            seeders: 5,
            size: 10_000_000
          })
        ]
      })

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"
      assert unit.below_floor_count == 0
    end

    test "a user-excluded release stops counting after the replan" do
      stub_recording_searches(%{
        "Sample Movie 2005" => [
          release("Sample.Movie.2005.720p.WEBRip.x264", "bf-720p", %{
            seeders: 9,
            size: 1_400_000_000
          })
        ]
      })

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})

      assert [unit] = Plans.units_for(plan.id)
      assert unit.below_floor_count == 1

      {:ok, _plan} = Plans.exclude_release(unit.id, "bf-720p")

      assert [replanned] = Plans.units_for(plan.id)
      assert replanned.status == "unfound"
      assert replanned.below_floor_count == 0
    end
  end

  describe "crash containment" do
    test "an unexpected raise records the error and resolves planning — never a stuck spinner" do
      # A non-binary title from the indexer crashes SearchResult
      # construction deep inside the run — standing in for any
      # unexpected raise. The moduledoc contract: failures mark the
      # plan's error and still transition to ready.
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [%{"title" => 123, "guid" => "garbage", "indexerId" => 1}])
      end)

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 1962})

      {:ok, reloaded} = Plans.fetch(plan.id)
      assert reloaded.status == "ready"
      assert reloaded.error =~ "planning crashed"
    end

    test "a plan discarded mid-run finishes quietly — not a recorded crash" do
      # Simulate a concurrent discard (user walks away) landing while the run
      # is mid-flight: the prowlarr stub discards the planning plan, so the
      # final `planning -> ready` transition can't apply. That is a normal
      # race, not a fault — it must not log `plan run crashed` (which mints a
      # spurious error incident).
      Req.Test.stub(:prowlarr, fn conn ->
        Enum.each(Plans.list_drafts(), &Plans.discard/1)
        Req.Test.json(conn, [])
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 1962})
          {:ok, reloaded} = Plans.fetch(plan.id)
          assert reloaded.status == "discarded"
        end)

      refute log =~ "plan run crashed"
    end
  end

  describe "cour-aware coverage guard" do
    # Air dates are synthetic; the shape mirrors a single TMDB season
    # split across broadcast runs (cours) the release world packages
    # separately — a "Season 01 COMPLETE" pack encoded before the later
    # cour aired. The guard caps each candidate to what it could
    # physically contain (aired on or before its publish date).

    # Season 1 spans two cours — E1–E3 (2023) and E4–E5 (2026). Stubbed
    # so the post-descent cour pass can segment and detect the later run.
    setup do
      TmdbStubs.setup_tmdb_client(self())

      TmdbStubs.stub_get_season("246810", 1, %{
        "episodes" => [
          %{"episode_number" => 1, "air_date" => "2023-10-01", "name" => "A"},
          %{"episode_number" => 2, "air_date" => "2023-10-08", "name" => "B"},
          %{"episode_number" => 3, "air_date" => "2023-10-15", "name" => "C"},
          %{"episode_number" => 4, "air_date" => "2026-01-16", "name" => "D"},
          %{"episode_number" => 5, "air_date" => "2026-01-23", "name" => "E"}
        ]
      })

      :ok
    end

    test "a season pack is not credited with episodes that aired after it was published" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "early-pack", %{
            seeders: 900,
            publishDate: "2024-06-01T00:00:00Z"
          })
        ]
      })

      # Want only the later-cour episodes, all aired after the pack was
      # published — exactly the silent never-completes case.
      {:ok, plan} =
        Plans.create_tracking_plan(
          %{tmdb_id: "246810", tmdb_type: "tv", title: "Sample Show"},
          [
            %{
              season_number: 1,
              episode_number: 4,
              air_date: ~D[2026-01-16],
              label: "S01E04",
              position: 0
            },
            %{
              season_number: 1,
              episode_number: 5,
              air_date: ~D[2026-01-23],
              label: "S01E05",
              position: 1
            }
          ]
        )

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.status == "unfound"))
      assert Enum.all?(units, &(&1.assigned_guid == nil))
      assert Enum.all?(units, &(&1.offered_guid == nil))

      # Coverage denied → the residual stayed non-empty → the descent
      # kept going to the episode rung instead of falsely halting.
      assert_received {:searched, "Sample Show S01E04"}
      assert_received {:searched, "Sample Show S01E05"}
    end

    test "the guard trims only the post-publish episodes — the pack still delivers the early ones" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "early-pack", %{
            seeders: 900,
            publishDate: "2024-06-01T00:00:00Z"
          })
        ]
      })

      {:ok, plan} =
        Plans.create_tracking_plan(
          %{tmdb_id: "246810", tmdb_type: "tv", title: "Sample Show"},
          [
            %{
              season_number: 1,
              episode_number: 1,
              air_date: ~D[2023-10-01],
              label: "S01E01",
              position: 0
            },
            %{
              season_number: 1,
              episode_number: 2,
              air_date: ~D[2023-10-08],
              label: "S01E02",
              position: 1
            },
            %{
              season_number: 1,
              episode_number: 4,
              air_date: ~D[2026-01-16],
              label: "S01E04",
              position: 2
            }
          ]
        )

      units = Plans.units_for(plan.id)
      early = Enum.filter(units, &(&1.episode_number in [1, 2]))
      late = Enum.find(units, &(&1.episode_number == 4))

      assert Enum.all?(early, &(&1.assigned_guid == "early-pack"))
      assert late.status == "unfound"
      assert late.assigned_guid == nil
    end

    test "a nil publish date does not trim (monotonic opt-in)" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "undated-pack", %{seeders: 900})
        ]
      })

      {:ok, plan} =
        Plans.create_tracking_plan(
          %{tmdb_id: "246810", tmdb_type: "tv", title: "Sample Show"},
          [
            %{
              season_number: 1,
              episode_number: 4,
              air_date: ~D[2026-01-16],
              label: "S01E04",
              position: 0
            },
            %{
              season_number: 1,
              episode_number: 5,
              air_date: ~D[2026-01-23],
              label: "S01E05",
              position: 1
            }
          ]
        )

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.assigned_guid == "undated-pack"))
    end

    test "a later-cour pack surfaces as an offer on the trimmed units (never auto-grabbed)" do
      # The first-run pack (2024) is found and trimmed by the guard, which
      # is the signal to search cour-shaped queries. The second-cour pack
      # is named "2nd Season", so plain ReleaseCoverage can't classify it —
      # the run-aware CourCoverage maps it to E4–E5 and offers it.
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "early-pack", %{
            seeders: 900,
            publishDate: "2024-06-01T00:00:00Z"
          })
        ],
        "Sample Show 2nd Season" => [
          release("Sample.Show.2nd.Season.1080p.BluRay", "cour2-pack", %{seeders: 50})
        ]
      })

      {:ok, plan} =
        Plans.create_tracking_plan(
          %{tmdb_id: "246810", tmdb_type: "tv", title: "Sample Show"},
          [
            %{
              season_number: 1,
              episode_number: 4,
              air_date: ~D[2026-01-16],
              label: "S01E04",
              position: 0
            },
            %{
              season_number: 1,
              episode_number: 5,
              air_date: ~D[2026-01-23],
              label: "S01E05",
              position: 1
            }
          ]
        )

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.status == "unfound"))
      assert Enum.all?(units, &(&1.assigned_guid == nil))
      assert Enum.all?(units, &(&1.offered_guid == "cour2-pack"))
      assert Enum.all?(units, &(&1.offered_scope == "S01E04-05"))
    end
  end

  defp descent_states(%PlanEvents.DescentStatus{stages: stages}) do
    Enum.map(stages, &{&1.id, &1.state})
  end

  describe "TV below-preference counting" do
    test "a show whose only releases are lower quality lands each unit unfound carrying its count" do
      stub_recording_searches(%{
        "Sample Show" => [
          release("Sample.Show.S02E01.DVDRip.x264", "tv-bf-dvd", %{seeders: 5, size: 300_000_000}),
          release("Sample.Show.S02E01.720p.WEBRip.x264", "tv-bf-720", %{
            seeders: 8,
            size: 900_000_000
          })
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{2, 1}])

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"
      assert unit.below_floor_count == 2

      board = plan.id |> Plans.fetch() |> then(fn {:ok, fetched} -> Plans.board_for(fetched) end)
      assert board.gaps == []
      refute board.lower_quality_accepted?

      assert %MediaCentaur.Acquisition.ViewModels.PlanBoard.BelowPreference{
               units: 1,
               releases: 2,
               unit_id: unit_id,
               unit_label: "S02E01 · Return"
             } = board.below_preference

      assert unit_id == unit.id

      assert [%{cells: [%{state: :below_preference}]}] = board.seasons
    end

    test "a below-preference pack counts for uncovered episodes while acceptable singles still assign" do
      stub_recording_searches(%{
        "Sample Show S01" => [
          release("Sample.Show.S01E01.1080p.WEB-DL.H.264", "tv-good-e1", %{
            seeders: 10,
            size: 2_000_000_000
          }),
          release("Sample.Show.S01.DVDRip.x264", "tv-bf-pack", %{seeders: 3, size: 2_500_000_000})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}])

      assert [first_episode, second_episode] =
               plan.id |> Plans.units_for() |> Enum.sort_by(& &1.episode_number)

      assert first_episode.status == "found"
      assert first_episode.assigned_guid == "tv-good-e1"
      assert first_episode.below_floor_count == 0

      assert second_episode.status == "unfound"
      assert second_episode.below_floor_count == 1
    end
  end

  describe "stop searching (ADR-063: status is the cancellation channel)" do
    test "a plan discarded mid-run stops before the next search term" do
      test_pid = self()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)
            send(test_pid, {:searched, query})
            Enum.each(Plans.list_drafts(), &Plans.discard/1)
            Req.Test.json(conn, [])

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, _plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {2, 1}])

      assert_received {:searched, "Sample Show"}
      refute_received {:searched, _any_later_term}
    end
  end

  describe "per-title quality bounds (ADR-063)" do
    test "a manual plan resolves a tracked title's any-minimum and assigns the lower-quality release" do
      item =
        MediaCentaur.ReleaseTracking.track_item!(%{
          tmdb_id: 246_810,
          media_type: :tv_series,
          name: "Sample Show",
          source: :manual
        })

      {:ok, _item} = MediaCentaur.ReleaseTracking.update_auto_grab(item, %{min_quality: "any"})

      stub_recording_searches(%{
        "Sample Show" => [
          release("Sample.Show.S02E01.DVDRip.x264", "sd-e1", %{seeders: 5, size: 300_000_000})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{2, 1}])

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "sd-e1"
    end

    test "accept_lower_quality tracks the title, stores the acceptance, and re-solves to the lower-quality release" do
      stub_recording_searches(%{
        "Sample Show" => [
          release("Sample.Show.S02E01.DVDRip.x264", "sd-e1", %{seeders: 5, size: 300_000_000})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{2, 1}])

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"
      assert unit.below_floor_count == 1

      {:ok, ready} = Plans.fetch(plan.id)
      {:ok, _plan} = Plans.accept_lower_quality(ready)

      item = MediaCentaur.ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)
      assert item.min_quality == "any"
      assert item.status == :watching

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "sd-e1"

      board = plan.id |> Plans.fetch() |> then(fn {:ok, fetched} -> Plans.board_for(fetched) end)
      assert board.lower_quality_accepted?
      assert board.below_preference == nil

      {:ok, accepted} = Plans.fetch(plan.id)
      {:ok, _plan} = Plans.undo_lower_quality(accepted)

      assert MediaCentaur.ReleaseTracking.get_item_by_tmdb(246_810, :tv_series).min_quality == nil

      board = plan.id |> Plans.fetch() |> then(fn {:ok, fetched} -> Plans.board_for(fetched) end)
      refute board.lower_quality_accepted?
    end
  end
end
