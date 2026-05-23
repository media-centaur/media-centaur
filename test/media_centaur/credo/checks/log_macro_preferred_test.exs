defmodule MediaCentaur.Credo.Checks.LogMacroPreferredTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.LogMacroPreferred

  describe "clean code (negative cases)" do
    test "MediaCentaur.Log macros in lib/media_centaur/ are allowed" do
      ~S'''
      defmodule MediaCentaur.Library do
        require MediaCentaur.Log, as: Log

        def doit do
          Log.info(:library, "did the thing")
          Log.warning(:library, "uh oh")
          Log.error(:library, "boom")
        end
      end
      '''
      |> to_source_file("lib/media_centaur/library.ex")
      |> run_check(LogMacroPreferred)
      |> refute_issues()
    end

    test "Logger calls in lib/media_centaur_web/ are allowed (Phoenix integration)" do
      ~S'''
      defmodule MediaCentaurWeb.Endpoint do
        require Logger

        def init do
          Logger.info("starting endpoint")
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/endpoint.ex")
      |> run_check(LogMacroPreferred)
      |> refute_issues()
    end

    test "Logger calls in MediaCentaur.Console.* are allowed (recursion bypass)" do
      ~S'''
      defmodule MediaCentaur.Console.Buffer do
        require Logger

        def persist_failed(error) do
          Logger.warning("buffer persist failed: #{inspect(error)}", mc_log_source: :buffer)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/console/buffer.ex")
      |> run_check(LogMacroPreferred)
      |> refute_issues()
    end

    test "Logger calls inside MediaCentaur.Log itself are allowed" do
      ~S'''
      defmodule MediaCentaur.Log do
        require Logger

        defmacro info(component, message) do
          quote do
            Logger.info(unquote(message), component: unquote(component))
          end
        end
      end
      '''
      |> to_source_file("lib/media_centaur/log.ex")
      |> run_check(LogMacroPreferred)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "Logger.info in lib/media_centaur/ context is reported" do
      ~S'''
      defmodule MediaCentaur.Library do
        require Logger

        def doit do
          Logger.info("did the thing")
        end
      end
      '''
      |> to_source_file("lib/media_centaur/library.ex")
      |> run_check(LogMacroPreferred)
      |> assert_issue()
    end

    test "Logger.warning in lib/media_centaur/ pipeline is reported" do
      ~S'''
      defmodule MediaCentaur.Pipeline.Stage do
        require Logger

        def run do
          Logger.warning("backlog")
        end
      end
      '''
      |> to_source_file("lib/media_centaur/pipeline/stage.ex")
      |> run_check(LogMacroPreferred)
      |> assert_issue()
    end

    test "Logger.error in lib/media_centaur/ is reported" do
      ~S'''
      defmodule MediaCentaur.Watcher do
        require Logger

        def event_failed do
          Logger.error("watcher boom")
        end
      end
      '''
      |> to_source_file("lib/media_centaur/watcher.ex")
      |> run_check(LogMacroPreferred)
      |> assert_issue()
    end
  end
end
