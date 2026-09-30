defmodule MediaCentaur.Acquisition.Jobs.GrabTargetTest do
  use MediaCentaur.DataCase, async: false
  use Oban.Testing, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Jobs.{GrabTarget, PursueTarget}
  alias MediaCentaur.Acquisition.Pursuits.Units
  alias MediaCentaur.Acquisition.{Target, TargetEvents, Targets}
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.JobRuns
  alias MediaCentaur.ProwlarrStubs
  alias MediaCentaur.Search.SearchResult

  setup do
    :ok = ProwlarrStubs.mark_ready!()
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_updates())
    :ok
  end

  defp chosen_release do
    %SearchResult{
      title: "Sample.Show.S01.COMPLETE.1080p.WEB-DL",
      guid: "chosen-1",
      indexer_id: 1,
      indexer_name: "Sample Indexer",
      quality: :hd_1080p,
      protocol: :usenet,
      size_bytes: 8_000_000_000
    }
  end

  # A two-episode pursuit: the chosen release is a pack covering both.
  defp pursuit_with_two_units do
    pursuit =
      create_pursuit(%{tmdb_type: "tv", title: "Sample Show", season_number: 1, episode_number: 1})

    create_pursuit_unit(pursuit, %{season_number: 1, episode_number: 2, position: 1})
    {pursuit, Units.for_pursuit(pursuit.id)}
  end

  defp grabbing_target do
    {pursuit, units} = pursuit_with_two_units()
    {:ok, target} = Targets.start_grabbing(pursuit, chosen_release(), units)
    {target, units}
  end

  defp grab_reply(reply) do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/v1/search"} -> reply.(conn)
        _other -> Req.Test.json(conn, [])
      end
    end)
  end

  defp perform(target), do: perform_job(GrabTarget, %{"target_id" => target.id})

  describe "Targets.start_grabbing/3" do
    test "writes the target, its coverage and the units' pointers, with its job in the transaction" do
      {pursuit, units} = pursuit_with_two_units()

      {{:ok, target}, inserts} =
        JobRuns.capture_inserts(fn -> Targets.start_grabbing(pursuit, chosen_release(), units) end)

      assert target.status == "grabbing"
      assert target.prowlarr_guid == "chosen-1"
      assert target.release_title == "Sample.Show.S01.COMPLETE.1080p.WEB-DL"

      assert Enum.sort(Enum.map(Units.covered_by(target.id), & &1.id)) ==
               Enum.sort(Enum.map(units, & &1.id))

      assert Enum.all?(units, &(Repo.reload!(&1).current_target_id == target.id))

      # Choosing the release is each unit's attempt, and marks it tried.
      for unit <- units do
        reloaded = Repo.reload!(unit)
        assert reloaded.attempt_count == 1
        assert reloaded.tried_release_guids == ["chosen-1"]
      end

      assert [%{in_transaction?: true, args: %{"target_id" => target_id}}] =
               Enum.filter(inserts, &(&1.worker == inspect(GrabTarget)))

      assert target_id == target.id
    end
  end

  describe "perform/1" do
    test "a grab Prowlarr accepts lands the target as acquired" do
      grab_reply(&Req.Test.json(&1, %{"approved" => true}))
      {target, _units} = grabbing_target()

      assert :ok = perform(target)

      acquired = Repo.reload!(target)
      assert acquired.status == "acquired"
      assert acquired.quality == "1080p"
      assert acquired.prowlarr_guid == "chosen-1"
      assert %DateTime{} = acquired.acquired_at
      assert_receive %TargetEvents.Acquired{target: %Target{status: "acquired"}}
    end

    test "a release Prowlarr refuses fails the target, and each unit it covered searches again" do
      grab_reply(&(&1 |> Plug.Conn.put_status(400) |> Req.Test.json(%{"message" => "bad release"})))
      {target, units} = grabbing_target()

      assert :ok = perform(target)

      assert Repo.reload!(target).status == "failed"

      for unit <- units do
        # The refused release is not tried again by the new search.
        assert "chosen-1" in Repo.reload!(unit).tried_release_guids

        seeking = Repo.get!(Target, Repo.reload!(unit).current_target_id)
        assert seeking.status == "seeking"
        refute seeking.id == target.id
        assert_enqueued(worker: PursueTarget, args: %{"target_id" => seeking.id})
      end
    end

    test "Prowlarr down: no grab, the target waits at the probe cadence" do
      Req.Test.stub(:prowlarr, fn _conn -> flunk("Prowlarr must not be called while it is down") end)
      {target, _units} = grabbing_target()
      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})

      assert {:snooze, 60} = perform(target)
      assert Repo.reload!(target).status == "grabbing"
    end

    test "a download client refusing the hand-off is an outage, not a bad release" do
      grab_reply(fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{
          "description" =>
            "NzbDrone.Core.Download.Clients.DownloadClientUnavailableException: Unable to connect to SABnzbd"
        })
      end)

      {target, _units} = grabbing_target()

      assert {:snooze, 60} = perform(target)

      waiting = Repo.reload!(target)
      assert waiting.status == "grabbing"
      assert waiting.last_attempt_outcome == "download_client_unavailable"
    end

    test "a target that is no longer grabbing is left alone" do
      Req.Test.stub(:prowlarr, fn _conn -> flunk("a cancelled target must not be grabbed") end)
      {target, _units} = grabbing_target()
      force_attrs(target, status: "cancelled")

      assert :ok = perform(target)
      assert Repo.reload!(target).status == "cancelled"
    end
  end
end
