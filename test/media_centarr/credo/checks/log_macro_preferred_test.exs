defmodule MediaCentarr.Credo.Checks.LogMacroPreferredTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.LogMacroPreferred

  describe "clean code (negative cases)" do
    test "MediaCentarr.Log macros in lib/media_centarr/ are allowed" do
      ~S'''
      defmodule MediaCentarr.Library do
        require MediaCentarr.Log, as: Log

        def doit do
          Log.info(:library, "did the thing")
          Log.warning(:library, "uh oh")
          Log.error(:library, "boom")
        end
      end
      '''
      |> to_source_file("lib/media_centarr/library.ex")
      |> run_check(LogMacroPreferred)
      |> refute_issues()
    end

    test "Logger calls in lib/media_centarr_web/ are allowed (Phoenix integration)" do
      ~S'''
      defmodule MediaCentarrWeb.Endpoint do
        require Logger

        def init do
          Logger.info("starting endpoint")
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/endpoint.ex")
      |> run_check(LogMacroPreferred)
      |> refute_issues()
    end

    test "Logger calls in MediaCentarr.Console.* are allowed (recursion bypass)" do
      ~S'''
      defmodule MediaCentarr.Console.Buffer do
        require Logger

        def persist_failed(error) do
          Logger.warning("buffer persist failed: #{inspect(error)}", mc_log_source: :buffer)
        end
      end
      '''
      |> to_source_file("lib/media_centarr/console/buffer.ex")
      |> run_check(LogMacroPreferred)
      |> refute_issues()
    end

    test "Logger calls inside MediaCentarr.Log itself are allowed" do
      ~S'''
      defmodule MediaCentarr.Log do
        require Logger

        defmacro info(component, message) do
          quote do
            Logger.info(unquote(message), component: unquote(component))
          end
        end
      end
      '''
      |> to_source_file("lib/media_centarr/log.ex")
      |> run_check(LogMacroPreferred)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "Logger.info in lib/media_centarr/ context is reported" do
      ~S'''
      defmodule MediaCentarr.Library do
        require Logger

        def doit do
          Logger.info("did the thing")
        end
      end
      '''
      |> to_source_file("lib/media_centarr/library.ex")
      |> run_check(LogMacroPreferred)
      |> assert_issue()
    end

    test "Logger.warning in lib/media_centarr/ pipeline is reported" do
      ~S'''
      defmodule MediaCentarr.Pipeline.Stage do
        require Logger

        def run do
          Logger.warning("backlog")
        end
      end
      '''
      |> to_source_file("lib/media_centarr/pipeline/stage.ex")
      |> run_check(LogMacroPreferred)
      |> assert_issue()
    end

    test "Logger.error in lib/media_centarr/ is reported" do
      ~S'''
      defmodule MediaCentarr.Watcher do
        require Logger

        def event_failed do
          Logger.error("watcher boom")
        end
      end
      '''
      |> to_source_file("lib/media_centarr/watcher.ex")
      |> run_check(LogMacroPreferred)
      |> assert_issue()
    end
  end
end
