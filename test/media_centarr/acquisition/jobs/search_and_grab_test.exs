defmodule MediaCentarr.Acquisition.Jobs.SearchAndGrabTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.{Grab, Jobs.SearchAndGrab, Prowlarr}
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
    end)

    :ok
  end

  defp job_for(grab), do: %Oban.Job{args: %{"grab_id" => grab.id}}

  # Default grab the suite uses targets a 2024 movie called "Sample Movie"
  # so the canned Sample.Movie.* release titles below pass title-matching.
  defp create_movie_grab(attrs \\ %{}) do
    defaults = %{title: "Sample Movie", year: 2024}
    create_grab(Map.merge(defaults, attrs))
  end

  defp four_kay_response do
    [
      %{
        "title" => "Sample.Movie.2024.2160p.UHD.BluRay.REMUX-FGT",
        "guid" => "uhd-guid",
        "indexerId" => 1,
        "seeders" => 10
      }
    ]
  end

  describe "perform/1 — 4K result found" do
    test "grabs the result, marks grab as grabbed with 4K quality, broadcasts" do
      grab = create_movie_grab()

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, four_kay_response()) end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      assert updated.quality == "4K"
      assert updated.grabbed_at != nil
      assert updated.last_attempt_at != nil
      assert updated.last_attempt_outcome == "grabbed"
      assert_received {:grab_submitted, %Grab{}}
    end
  end

  describe "perform/1 — only 1080p found" do
    test "grabs the 1080p result and marks grab as grabbed" do
      grab = create_movie_grab()

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Movie.2024.1080p.WEB-DL.H264-NTG",
            "guid" => "hd-guid",
            "indexerId" => 1,
            "seeders" => 25
          }
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      assert updated.quality == "1080p"
    end
  end

  describe "perform/1 — 4K preferred over 1080p when both available" do
    test "grabs the 4K result, not the 1080p" do
      grab = create_movie_grab()

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{"title" => "Sample.Movie.2024.1080p.WEB-DL", "guid" => "hd-guid", "indexerId" => 1},
          %{
            "title" => "Sample.Movie.2024.2160p.UHD.BluRay",
            "guid" => "uhd-guid",
            "indexerId" => 1
          }
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.quality == "4K"
    end
  end

  describe "perform/1 — nothing acceptable found" do
    test "first attempt: snoozes 4h, increments attempt_count, marks status snoozed, broadcasts" do
      grab = create_movie_grab()

      assert {:snooze, snooze_seconds} = SearchAndGrab.perform(job_for(grab))
      assert snooze_seconds == 4 * 60 * 60

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "snoozed"
      assert updated.attempt_count == 1
      assert updated.last_attempt_outcome == "no_results"
      assert updated.last_attempt_at != nil
      assert_received {:auto_grab_snoozed, %Grab{}}
    end

    test "exponential backoff: attempt 2 → 8h, attempt 3 → 16h, attempt 4 → 24h cap" do
      grab = create_movie_grab(%{attempt_count: 1})
      assert {:snooze, seconds} = SearchAndGrab.perform(job_for(grab))
      assert seconds == 8 * 60 * 60

      grab = create_movie_grab(%{tmdb_id: "22222", attempt_count: 2})
      assert {:snooze, seconds} = SearchAndGrab.perform(job_for(grab))
      assert seconds == 16 * 60 * 60

      grab = create_movie_grab(%{tmdb_id: "33333", attempt_count: 3})
      assert {:snooze, seconds} = SearchAndGrab.perform(job_for(grab))
      assert seconds == 24 * 60 * 60

      grab = create_movie_grab(%{tmdb_id: "44444", attempt_count: 9})
      assert {:snooze, seconds} = SearchAndGrab.perform(job_for(grab))
      assert seconds == 24 * 60 * 60
    end

    test "only 720p available — does not grab, marks no_acceptable_quality, increments attempt" do
      grab = create_movie_grab()

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Movie.2024.720p.BluRay.x264",
            "guid" => "sd-guid",
            "indexerId" => 1
          }
        ])
      end)

      assert {:snooze, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.attempt_count == 1
      assert updated.last_attempt_outcome == "no_acceptable_quality"
    end
  end

  describe "perform/1 — abandonment" do
    test "after max_attempts no-results: marks abandoned, broadcasts, returns :ok (no snooze)" do
      grab = create_movie_grab(%{attempt_count: 11})

      assert :ok = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "abandoned"
      assert updated.cancelled_reason == "abandoned"
      assert updated.cancelled_at != nil
      assert_received {:auto_grab_abandoned, %Grab{}}
    end
  end

  describe "perform/1 — Prowlarr error" do
    test "snoozes 1h, does NOT increment attempt_count, marks prowlarr_error" do
      grab = create_movie_grab(%{attempt_count: 3})

      Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)

      assert {:snooze, snooze_seconds} = SearchAndGrab.perform(job_for(grab))
      assert snooze_seconds == 60 * 60

      updated = Repo.get!(Grab, grab.id)
      assert updated.attempt_count == 3
      assert updated.status == "snoozed"
      assert updated.last_attempt_outcome == "prowlarr_error"
      assert_received {:auto_grab_snoozed, %Grab{}}
    end
  end

  describe "perform/1 — terminal-state early exit" do
    test "grabbed grab returns :ok without searching or counting attempts" do
      grab = create_grab(%{tmdb_id: "exit-1"})
      {:ok, grabbed} = Repo.update(Grab.grabbed_changeset(grab, "4K"))

      assert {:ok, :already_grabbed} = SearchAndGrab.perform(job_for(grabbed))

      updated = Repo.get!(Grab, grab.id)
      assert updated.attempt_count == 0
    end

    test "cancelled grab early-exits without searching" do
      grab = create_grab(%{tmdb_id: "exit-2"})
      {:ok, cancelled} = Repo.update(Grab.cancelled_changeset(grab, "in_library"))

      assert {:ok, :cancelled} = SearchAndGrab.perform(job_for(cancelled))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "cancelled"
      assert updated.attempt_count == 0
    end

    test "abandoned grab early-exits without searching" do
      grab = create_grab(%{tmdb_id: "exit-3"})
      {:ok, abandoned} = Repo.update(Grab.abandoned_changeset(grab))

      assert {:ok, :abandoned} = SearchAndGrab.perform(job_for(abandoned))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "abandoned"
    end
  end

  describe "perform/1 — TV episode query construction" do
    test "uses 'Title SxxExx' query for an episode grab" do
      grab =
        create_grab(%{
          tmdb_id: "999",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 3,
          episode_number: 4
        })

      received_queries = :ets.new(:queries, [:public, :ordered_set])

      Req.Test.stub(:prowlarr, fn conn ->
        query = conn.query_params["query"]
        :ets.insert(received_queries, {System.unique_integer([:monotonic]), query})

        Req.Test.json(conn, [
          %{
            "title" => "Sample.Show.S03E04.2160p.UHD.WEB-DL.DDP5.1.H.265-GROUP",
            "guid" => "tv-uhd-guid",
            "indexerId" => 1,
            "seeders" => 10
          }
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      [{_, first_query}] = :ets.lookup(received_queries, :ets.first(received_queries))
      assert first_query == "Sample Show S03E04"
    end
  end

  describe "perform/1 — title-match gating" do
    test "rejects results that do not parse to the requested show (the Sample Show Fifteen bug)" do
      # User tracks a show called "Sample Show Fifteen". Prowlarr returns garbage:
      # an episode of an unrelated show whose episode title is "Sample Show Fifteen",
      # and a different show that just contains the word.
      # Pre-fix the worker grabbed the first 1080p result regardless;
      # post-fix every result must parse to the requested show.
      grab =
        create_grab(%{
          tmdb_id: "paradise-1",
          tmdb_type: "tv",
          title: "Sample Show Fifteen",
          season_number: 1,
          episode_number: 1
        })

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Show.S01E05.Sample Show Fifteen.1080p.WEB-DL.x264-GROUP",
            "guid" => "wrong-show-guid",
            "indexerId" => 1,
            "seeders" => 50
          },
          %{
            "title" => "Sample Show Fifteen.PD.S01E01.1080p.WEB-DL.x264-GROUP",
            "guid" => "wrong-paradise-guid",
            "indexerId" => 1,
            "seeders" => 30
          }
        ])
      end)

      assert {:snooze, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "snoozed"
      assert updated.last_attempt_outcome == "no_title_match"
      assert updated.attempt_count == 1
    end

    test "accepts the matching result even when junk results outrank it" do
      grab =
        create_grab(%{
          tmdb_id: "paradise-2",
          tmdb_type: "tv",
          title: "Sample Show Fifteen",
          season_number: 1,
          episode_number: 1
        })

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Show.S01E05.Sample Show Fifteen.1080p.WEB-DL.x264-GROUP",
            "guid" => "wrong-show-guid",
            "indexerId" => 1,
            "seeders" => 200
          },
          %{
            "title" => "Sample Show Fifteen.S01E01.1080p.WEB-DL.x264-GROUP",
            "guid" => "right-guid",
            "indexerId" => 1,
            "seeders" => 5
          }
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      assert updated.quality == "1080p"
    end
  end

  describe "perform/1 — grab record not found" do
    test "returns ok gracefully for unknown grab_id" do
      job = %Oban.Job{args: %{"grab_id" => Ecto.UUID.generate()}}
      assert {:ok, :not_found} = SearchAndGrab.perform(job)
    end
  end

  describe "perform/1 — 4K patience window" do
    test "within patience window with max=4K: 1080p result is REJECTED, snoozes" do
      grab =
        create_movie_grab(%{
          tmdb_id: "patience-1",
          min_quality: "hd_1080p",
          max_quality: "uhd_4k",
          quality_4k_patience_hours: 48,
          # Place inserted_at recently so we are inside the 48h window.
          inserted_at: DateTime.add(DateTime.utc_now(:second), -1, :hour)
        })

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{"title" => "Sample.Movie.2024.1080p.WEB-DL", "guid" => "h", "indexerId" => 1}
        ])
      end)

      assert {:snooze, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.last_attempt_outcome == "no_acceptable_quality"
      assert updated.status == "snoozed"
    end

    test "outside patience window: 1080p result is ACCEPTED" do
      grab =
        create_movie_grab(%{
          tmdb_id: "patience-2",
          min_quality: "hd_1080p",
          max_quality: "uhd_4k",
          quality_4k_patience_hours: 48,
          inserted_at: DateTime.add(DateTime.utc_now(:second), -49, :hour)
        })

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{"title" => "Sample.Movie.2024.1080p.WEB-DL", "guid" => "h", "indexerId" => 1}
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      assert updated.quality == "1080p"
    end

    test "patience disabled (0 hours): 1080p accepted immediately even with 4K max" do
      grab =
        create_movie_grab(%{
          tmdb_id: "patience-3",
          min_quality: "hd_1080p",
          max_quality: "uhd_4k",
          quality_4k_patience_hours: 0,
          inserted_at: DateTime.utc_now(:second)
        })

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{"title" => "Sample.Movie.2024.1080p.WEB-DL", "guid" => "h", "indexerId" => 1}
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
    end

    test "even within patience, a 4K result IS grabbed (only 1080p is held back)" do
      grab =
        create_movie_grab(%{
          tmdb_id: "patience-4",
          min_quality: "hd_1080p",
          max_quality: "uhd_4k",
          quality_4k_patience_hours: 48,
          inserted_at: DateTime.utc_now(:second)
        })

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, four_kay_response()) end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      assert updated.quality == "4K"
    end

    test "1080p-only bounds (max=hd_1080p): patience irrelevant, 1080p accepted immediately" do
      grab =
        create_movie_grab(%{
          tmdb_id: "patience-5",
          min_quality: "hd_1080p",
          max_quality: "hd_1080p",
          quality_4k_patience_hours: 48,
          inserted_at: DateTime.utc_now(:second)
        })

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{"title" => "Sample.Movie.2024.1080p.WEB-DL", "guid" => "h", "indexerId" => 1}
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
    end
  end

  # The grab row carries no exclusion array of its own — the linked
  # pursuit's `tried_release_guids` is the source of truth, populated
  # by `Commands.RecordUserChoice` when the user picks an alternative.
  describe "perform/1 — pursuit tried_release_guids" do
    defp grab_with_tried_pursuit(tried) do
      pursuit = create_pursuit(%{title: "Sample Movie", year: 2024})

      pursuit
      |> Ecto.Changeset.change(tried_release_guids: tried)
      |> Repo.update!()

      grab = create_movie_grab()

      grab
      |> Ecto.Changeset.change(pursuit_id: pursuit.id)
      |> Repo.update!()
    end

    test "skips releases whose guid is in the pursuit's tried list, picks the next best" do
      grab = grab_with_tried_pursuit(["uhd-guid"])

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Movie.2024.2160p.UHD.BluRay.REMUX-FGT",
            "guid" => "uhd-guid",
            "indexerId" => 1,
            "seeders" => 10
          },
          %{
            "title" => "Sample.Movie.2024.1080p.WEB-DL.H264-NTG",
            "guid" => "hd-guid",
            "indexerId" => 1,
            "seeders" => 25
          }
        ])
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      # 1080p result picked because UHD result was excluded
      assert updated.quality == "1080p"
    end

    test "snoozes when every result is in the pursuit's tried list" do
      grab = grab_with_tried_pursuit(["only-guid"])

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{
            "title" => "Sample.Movie.2024.2160p.UHD.BluRay.REMUX-FGT",
            "guid" => "only-guid",
            "indexerId" => 1,
            "seeders" => 10
          }
        ])
      end)

      assert {:snooze, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "snoozed"
    end

    test "no linked pursuit leaves behavior unchanged (legacy grab)" do
      grab = create_movie_grab()

      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, four_kay_response())
      end)

      assert {:ok, _} = SearchAndGrab.perform(job_for(grab))

      updated = Repo.get!(Grab, grab.id)
      assert updated.status == "grabbed"
      assert updated.quality == "4K"
    end
  end
end
