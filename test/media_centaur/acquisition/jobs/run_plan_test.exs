defmodule MediaCentaur.Acquisition.Jobs.RunPlanTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Targeting
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
      Map.new(Map.delete(attrs, :seeders), fn {key, value} -> {to_string(key), value} end)
    )
  end

  # Serves results_by_query and reports every live GET search back to
  # the test process — the descent assertions read the mailbox.
  defp stub_recording_searches(results_by_query) do
    test_pid = self()

    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
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

  defp descent_states(%PlanEvents.DescentStatus{stages: stages}) do
    Enum.map(stages, &{&1.id, &1.state})
  end
end
