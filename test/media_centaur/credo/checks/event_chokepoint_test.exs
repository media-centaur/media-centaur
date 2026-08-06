defmodule MediaCentaur.Credo.Checks.EventChokepointTest do
  @moduledoc """
  The three chokepoint checks (MC0012, MC0013, MC0026) share one matcher.
  These tests pin the payload arities and call spellings it must catch —
  MC0012 and MC0013 were both verified vacuous against a real violation
  before this matcher replaced their hand-rolled AST clauses.
  """
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.LibraryUpdatesContract
  alias MediaCentaur.Credo.Checks.PlaybackEventsContract
  alias MediaCentaur.Credo.Checks.ReviewUpdatesContract

  describe "MC0013 — library:updates (was vacuous)" do
    test "a two-element tuple payload is caught" do
      ~S'''
      defmodule MediaCentaur.Sneaky do
        def go(event) do
          Phoenix.PubSub.broadcast(MediaCentaur.PubSub, "library:updates", {:entities_changed, event})
        end
      end
      '''
      |> to_source_file("lib/media_centaur/sneaky.ex")
      |> run_check(LibraryUpdatesContract)
      |> assert_issue()
    end

    test "the Topics.publish spelling is caught" do
      ~S'''
      defmodule MediaCentaur.Sneaky do
        def go(event) do
          Topics.publish(Topics.library_updates(), {:entities_changed, event})
        end
      end
      '''
      |> to_source_file("lib/media_centaur/sneaky.ex")
      |> run_check(LibraryUpdatesContract)
      |> assert_issue()
    end

    test "the chokepoint itself is exempt" do
      ~S'''
      defmodule MediaCentaur.Library.Events do
        def broadcast(event), do: Topics.publish(Topics.library_updates(), {:entities_changed, event})
      end
      '''
      |> to_source_file("lib/media_centaur/library/events.ex")
      |> run_check(LibraryUpdatesContract)
      |> refute_issues()
    end

    test "going through the chokepoint is clean" do
      ~S'''
      defmodule MediaCentaur.Library.Inbound do
        alias MediaCentaur.Library.Events
        alias MediaCentaur.Library.Events.EntitiesChanged

        def go(ids), do: Events.broadcast(%EntitiesChanged{entity_ids: ids})
      end
      '''
      |> to_source_file("lib/media_centaur/library/inbound.ex")
      |> run_check(LibraryUpdatesContract)
      |> refute_issues()
    end

    test "an unrelated tag on another topic is left alone" do
      ~S'''
      defmodule MediaCentaur.Sneaky do
        def go(id), do: Topics.publish(Topics.status_views(), {:status_view_updated, id})
      end
      '''
      |> to_source_file("lib/media_centaur/sneaky.ex")
      |> run_check(LibraryUpdatesContract)
      |> refute_issues()
    end
  end

  describe "MC0012 — playback:events (was vacuous)" do
    test "a two-element tuple payload is caught" do
      ~S'''
      defmodule MediaCentaur.Sneaky do
        def go(payload) do
          Phoenix.PubSub.broadcast(MediaCentaur.PubSub, "playback:events", {:playback_failed, payload})
        end
      end
      '''
      |> to_source_file("lib/media_centaur/sneaky.ex")
      |> run_check(PlaybackEventsContract)
      |> assert_issue()
    end

    test "the legacy positional five-tuple is still caught" do
      ~S'''
      defmodule MediaCentaur.Sneaky do
        def go(id, state, np, ts) do
          Topics.publish(Topics.playback_events(), {:playback_state_changed, id, state, np, ts})
        end
      end
      '''
      |> to_source_file("lib/media_centaur/sneaky.ex")
      |> run_check(PlaybackEventsContract)
      |> assert_issue()
    end
  end

  describe "MC0026 — review:updates" do
    test "publishing a review tag directly is caught" do
      ~S'''
      defmodule MediaCentaur.Review.Intake do
        def go(id), do: Topics.publish(Topics.review_updates(), {:file_added, id})
      end
      '''
      |> to_source_file("lib/media_centaur/review/intake.ex")
      |> run_check(ReviewUpdatesContract)
      |> assert_issue()
    end

    test "the old positional group tuple is caught" do
      ~S'''
      defmodule MediaCentaur.Review do
        def go(key, message), do: Topics.publish(Topics.review_updates(), {:group_error, key, message})
      end
      '''
      |> to_source_file("lib/media_centaur/review.ex")
      |> run_check(ReviewUpdatesContract)
      |> assert_issue()
    end

    test "each direct publication is reported separately" do
      ~S'''
      defmodule MediaCentaur.Review do
        def go(key, count, id) do
          Topics.publish(Topics.review_updates(), {:group_approved, key, count})
          Topics.publish(Topics.review_updates(), {:file_reviewed, id})
        end
      end
      '''
      |> to_source_file("lib/media_centaur/review.ex")
      |> run_check(ReviewUpdatesContract)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end

    test "going through the chokepoint is clean" do
      ~S'''
      defmodule MediaCentaur.Review.Intake do
        alias MediaCentaur.Review.Events
        alias MediaCentaur.Review.Events.FileAdded

        def go(id), do: Events.broadcast(%FileAdded{pending_file_id: id})
      end
      '''
      |> to_source_file("lib/media_centaur/review/intake.ex")
      |> run_check(ReviewUpdatesContract)
      |> refute_issues()
    end

    test "the chokepoint itself is exempt" do
      ~S'''
      defmodule MediaCentaur.Review.Events do
        def broadcast(event), do: Topics.publish(Topics.review_updates(), {:file_added, event})
      end
      '''
      |> to_source_file("lib/media_centaur/review/events.ex")
      |> run_check(ReviewUpdatesContract)
      |> refute_issues()
    end

    test "test files may publish directly" do
      ~S'''
      defmodule MediaCentaur.ReviewTest do
        test "fan-in" do
          Topics.publish(Topics.review_updates(), {:file_added, "id"})
        end
      end
      '''
      |> to_source_file("test/media_centaur/review_test.exs")
      |> run_check(ReviewUpdatesContract)
      |> refute_issues()
    end

    test "a payload the matcher cannot read statically is not guessed at" do
      ~S'''
      defmodule MediaCentaur.Sneaky do
        def go(message), do: Topics.publish(Topics.review_updates(), message)
      end
      '''
      |> to_source_file("lib/media_centaur/sneaky.ex")
      |> run_check(ReviewUpdatesContract)
      |> refute_issues()
    end
  end
end
