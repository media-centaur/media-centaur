defmodule MediaCentaur.Credo.Checks.LogComponentMatchesContextTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.LogComponentMatchesContext

  describe "clean code (negative cases)" do
    test "a context logging as its own component is allowed" do
      ~S'''
      defmodule MediaCentaur.Review.Intake do
        def run, do: Log.info(:review, "claimed a file")
      end
      '''
      |> to_source_file("lib/media_centaur/review/intake.ex")
      |> run_check(LogComponentMatchesContext)
      |> refute_issues()
    end

    test "a context that shares another's component is allowed" do
      ~S'''
      defmodule MediaCentaur.Downloads.QueueMonitor do
        def run, do: Log.warning(:acquisition, "client unreachable")
      end
      '''
      |> to_source_file("lib/media_centaur/downloads/queue_monitor.ex")
      |> run_check(LogComponentMatchesContext)
      |> refute_issues()
    end

    test "the web layer logs about the domain it displays" do
      ~S'''
      defmodule MediaCentaurWeb.IncomingLive do
        def run, do: Log.info(:acquisition, "user approved a plan")
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/incoming_live.ex")
      |> run_check(LogComponentMatchesContext)
      |> refute_issues()
    end

    test "an unmapped context is left alone" do
      ~S'''
      defmodule MediaCentaur.Guide.Pages do
        def run, do: Log.info(:library, "rendered a page")
      end
      '''
      |> to_source_file("lib/media_centaur/guide/pages.ex")
      |> run_check(LogComponentMatchesContext)
      |> refute_issues()
    end

    test "a non-literal component is left alone" do
      ~S'''
      defmodule MediaCentaur.Review.Intake do
        def run(component), do: Log.info(component, "dynamic")
      end
      '''
      |> to_source_file("lib/media_centaur/review/intake.ex")
      |> run_check(LogComponentMatchesContext)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "review code tagging :library is reported" do
      ~S'''
      defmodule MediaCentaur.Review.Intake do
        def run, do: Log.info(:library, "claimed a file")
      end
      '''
      |> to_source_file("lib/media_centaur/review/intake.ex")
      |> run_check(LogComponentMatchesContext)
      |> assert_issue()
    end

    test "release-tracking code tagging :library is reported" do
      ~S'''
      defmodule MediaCentaur.ReleaseTracking.Refresher do
        def run, do: Log.error(:library, "refresh failed")
      end
      '''
      |> to_source_file("lib/media_centaur/release_tracking/refresher.ex")
      |> run_check(LogComponentMatchesContext)
      |> assert_issue()
    end

    test "a context's root module file is held to the same rule" do
      ~S'''
      defmodule MediaCentaur.Review do
        def run, do: Log.info(:library, "reviewed")
      end
      '''
      |> to_source_file("lib/media_centaur/review.ex")
      |> run_check(LogComponentMatchesContext)
      |> assert_issue()
    end
  end
end
