defmodule MediaCentaur.Acquisition.Pursuits.InboundListenerTest do
  use MediaCentaur.DataCase, async: false

  import Ecto.Query

  alias MediaCentaur.Acquisition.Pursuits.InboundListener

  defp insert_pursuit(overrides), do: create_pursuit(overrides)

  defp set_state(pursuit, new_state) do
    force_state(pursuit, new_state)
  end

  defp enqueued_jobs do
    Repo.all(from j in Oban.Job, where: j.worker == "MediaCentaur.Acquisition.Pursuits.IdentityVerifier")
  end

  defp run(event) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      InboundListener.dispatch(event)
    end)
  end

  describe "dispatch/1 — movie events" do
    test "enqueues IdentityVerifier for an active matching movie pursuit" do
      pursuit = insert_pursuit(%{tmdb_id: "555", tmdb_type: "movie", title: "Movie A"})

      event = %{
        entity_type: :movie,
        identifier: %{source: "tmdb", external_id: "555"},
        season: nil,
        file_path: "/watch/Movie.A.2024.1080p.WEB-DL.mkv"
      }

      assert 1 = run(event)

      [job] = enqueued_jobs()
      assert job.args["pursuit_id"] == pursuit.id
      assert job.args["file_path"] == "/watch/Movie.A.2024.1080p.WEB-DL.mkv"
      assert job.queue == "acquisition"
    end

    test "ignores events with no matching active pursuit" do
      _other = insert_pursuit(%{tmdb_id: "999", tmdb_type: "movie"})

      event = %{
        entity_type: :movie,
        identifier: %{source: "tmdb", external_id: "555"},
        season: nil,
        file_path: "/watch/x.mkv"
      }

      assert 0 = run(event)
      assert [] = enqueued_jobs()
    end

    test "skips terminal-state pursuits even when tmdb_id matches" do
      pursuit = insert_pursuit(%{tmdb_id: "555", tmdb_type: "movie"})
      set_state(pursuit, "satisfied")

      event = %{
        entity_type: :movie,
        identifier: %{source: "tmdb", external_id: "555"},
        season: nil,
        file_path: "/watch/x.mkv"
      }

      assert 0 = run(event)
    end
  end

  describe "dispatch/1 — TV events" do
    test "enqueues IdentityVerifier for a TV pursuit matching tmdb_id + season + episode" do
      pursuit =
        insert_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 2,
          episode_number: 5
        })

      event = %{
        entity_type: :tv_series,
        identifier: %{source: "tmdb", external_id: "777"},
        season: %{
          season_number: 2,
          name: "Season 2",
          number_of_episodes: 10,
          episode: %{attrs: %{episode_number: 5}, images: []}
        },
        file_path: "/watch/Sample.Show.S02E05.mkv"
      }

      assert 1 = run(event)

      [job] = enqueued_jobs()
      assert job.args["pursuit_id"] == pursuit.id

      # Unit identity rides along so the verifier satisfies the landed
      # unit — never the lead (campaign pursuit-identity-and-lifecycle).
      assert job.args["season_number"] == 2
      assert job.args["episode_number"] == 5
    end

    test "does not match a different episode of the same series" do
      _wrong =
        insert_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 2,
          episode_number: 6
        })

      event = %{
        entity_type: :tv_series,
        identifier: %{source: "tmdb", external_id: "777"},
        season: %{
          season_number: 2,
          name: "Season 2",
          number_of_episodes: 10,
          episode: %{attrs: %{episode_number: 5}, images: []}
        },
        file_path: "/watch/x.mkv"
      }

      assert 0 = run(event)
    end

    test "season-pack pursuit (no episode pin) matches any episode" do
      pursuit =
        insert_pursuit(%{
          tmdb_id: "777",
          tmdb_type: "tv",
          title: "Sample Show"
        })

      event = %{
        entity_type: :tv_series,
        identifier: %{source: "tmdb", external_id: "777"},
        season: %{
          season_number: 2,
          name: "Season 2",
          number_of_episodes: 10,
          episode: %{attrs: %{episode_number: 5}, images: []}
        },
        file_path: "/watch/Sample.Show.S02E05.mkv"
      }

      assert 1 = run(event)

      [job] = enqueued_jobs()
      assert job.args["pursuit_id"] == pursuit.id
    end
  end

  describe "dispatch/1 — non-matching events" do
    test "ignores events with non-tmdb identifier source" do
      _movie = insert_pursuit(%{tmdb_id: "555", tmdb_type: "movie"})

      event = %{
        entity_type: :movie_series,
        identifier: %{source: "tmdb_collection", external_id: "555"},
        season: nil,
        file_path: "/watch/x.mkv"
      }

      assert 0 = run(event)
    end

    test "ignores video_object events (extras don't have pursuits in v1)" do
      event = %{
        entity_type: :video_object,
        identifier: %{source: "tmdb", external_id: "555"},
        season: nil,
        file_path: "/watch/x.mkv"
      }

      assert 0 = run(event)
    end

    test "tolerates malformed events gracefully" do
      assert 0 = run(%{})
      assert 0 = run(%{entity_type: :movie})
    end
  end

  describe "GenServer wiring" do
    test "init/1 subscribes to pipeline:publish" do
      {:ok, _state} = InboundListener.init([])

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        MediaCentaur.Topics.pipeline_publish(),
        :ping_test
      )

      assert_receive :ping_test, 500
    end
  end
end
