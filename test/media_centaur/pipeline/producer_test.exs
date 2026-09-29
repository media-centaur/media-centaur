defmodule MediaCentaur.Pipeline.ProducerTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Pipeline.Discovery.Producer, as: DiscoveryProducer
  alias MediaCentaur.Pipeline.Import.Producer, as: ImportProducer
  alias MediaCentaur.Pipeline.Payload

  describe "DiscoveryProducer.build_payload/1" do
    test "builds payload with file_path and media_directory" do
      payload =
        DiscoveryProducer.build_payload(%{
          path: "/media/movies/Fight.Club.1999.mkv",
          media_dir: "/media/movies"
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/movies/Fight.Club.1999.mkv"
      assert payload.media_directory == "/media/movies"
      assert payload.tmdb_id == nil
      assert payload.tmdb_type == nil
    end
  end

  describe "ImportProducer.build_payload/1" do
    test "builds payload with the whole match: tmdb id, type, season and episode" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/tv/Sample.Special.2025.mkv",
          media_dir: "/media/tv",
          tmdb_id: 1396,
          tmdb_type: :tv,
          season: 1,
          episode: 22
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/tv/Sample.Special.2025.mkv"
      assert payload.media_directory == "/media/tv"
      assert payload.tmdb_id == 1396
      assert payload.tmdb_type == :tv
      assert payload.match_season == 1
      assert payload.match_episode == 22
    end

    # The match decides where the file goes. A message without season and
    # episode would let Import fall back to guessing them from the path,
    # which is how a reviewer's choice used to be ignored.
    test "a match without season and episode is refused" do
      # Built at runtime: the type checker already rejects the literal.
      incomplete =
        Function.identity(%{
          file_path: "/media/movies/Sample.Movie.1999.mkv",
          media_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: :movie
        })

      assert_raise FunctionClauseError, fn -> ImportProducer.build_payload(incomplete) end
    end

    test "normalizes string tmdb_type to atom" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/tv/Some.Show.S01E01.mkv",
          media_dir: "/media/tv",
          tmdb_id: 1399,
          tmdb_type: "tv",
          season: nil,
          episode: nil
        })

      assert payload.tmdb_type == :tv
    end

    test "normalizes movie string tmdb_type to atom" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/movies/Movie.mkv",
          media_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: "movie",
          season: nil,
          episode: nil
        })

      assert payload.tmdb_type == :movie
    end
  end

  describe "DiscoveryProducer.recover_action/2" do
    test "runs immediately once the watcher reports running, regardless of attempt count" do
      assert DiscoveryProducer.recover_action(0, true) == :run
      assert DiscoveryProducer.recover_action(19, true) == :run
    end

    test "retries with a delay while the watcher isn't running yet and attempts remain" do
      assert {:retry, delay} = DiscoveryProducer.recover_action(0, false)
      # `is_integer(delay)` is proven by the type checker since Elixir 1.20
      # (asserting it is a compile warning); the bound is the real check.
      assert delay > 0
    end

    test "gives up silently once the attempt budget is exhausted" do
      # Startup recovery is a one-time opportunity racing against
      # `MediaCentaur.Watcher.Supervisor.start_watchers/0` (ADR-023) — it must
      # not retry forever, and it must not treat a deliberately-disabled
      # watcher (`services:*:start_watchers` off) as an error worth logging.
      assert DiscoveryProducer.recover_action(DiscoveryProducer.max_recover_attempts(), false) ==
               :skip
    end
  end
end
