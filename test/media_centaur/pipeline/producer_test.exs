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
    # Changed 2026-09-29 (campaign `review-coherence`): the match carried a
    # season and episode so a reviewer's episode choice reached Import.
    # Review no longer chooses one — a position is decided in episode
    # mapping — so the match is the identity and Import parses the claim.
    test "builds payload with the match's identity: tmdb id and type" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/tv/Sample.Special.2025.mkv",
          media_dir: "/media/tv",
          tmdb_id: 1396,
          tmdb_type: :tv
        })

      assert %Payload{} = payload
      assert payload.file_path == "/media/tv/Sample.Special.2025.mkv"
      assert payload.media_directory == "/media/tv"
      assert payload.tmdb_id == 1396
      assert payload.tmdb_type == :tv
    end

    # Changed 2026-09-29 (campaign `review-coherence`): this refused a match
    # without season and episode. What a match cannot lack now is its
    # identity — one without a type once crashed the producer and lost the
    # imports queued behind it.
    test "a match without an identity is refused" do
      # Built at runtime: the type checker already rejects the literal.
      incomplete =
        Function.identity(%{
          file_path: "/media/movies/Sample.Movie.1999.mkv",
          media_dir: "/media/movies",
          tmdb_id: 550
        })

      assert_raise FunctionClauseError, fn -> ImportProducer.build_payload(incomplete) end
    end

    test "normalizes string tmdb_type to atom" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/tv/Some.Show.S01E01.mkv",
          media_dir: "/media/tv",
          tmdb_id: 1399,
          tmdb_type: "tv"
        })

      assert payload.tmdb_type == :tv
    end

    test "normalizes movie string tmdb_type to atom" do
      payload =
        ImportProducer.build_payload(%{
          file_path: "/media/movies/Movie.mkv",
          media_dir: "/media/movies",
          tmdb_id: 550,
          tmdb_type: "movie"
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
