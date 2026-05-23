defmodule MediaCentaur.Credo.Checks.PlatformBranchingDisciplineTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.PlatformBranchingDiscipline

  describe "clean code (negative cases)" do
    test "code inside lib/media_centaur/platform/ may call :os.type/0" do
      ~S'''
      defmodule MediaCentaur.Platform.WatcherEvents do
        def normalize(events) do
          case :os.type() do
            {:unix, :darwin} -> macos_translate(events)
            _ -> events
          end
        end
      end
      '''
      |> to_source_file("lib/media_centaur/platform/watcher_events.ex")
      |> run_check(PlatformBranchingDiscipline)
      |> refute_issues()
    end

    test "code outside lib/ is not analysed (tests, scripts)" do
      ~S'''
      defmodule SomeTest do
        test "things" do
          assert :os.type() == {:unix, :linux}
        end
      end
      '''
      |> to_source_file("test/some_test.exs")
      |> run_check(PlatformBranchingDiscipline)
      |> refute_issues()
    end

    test "grandfathered files are skipped" do
      ~S'''
      defmodule MediaCentaur.ErrorReports.EnvMetadata do
        def collect do
          {family, name} = :os.type()
          {family, name}
        end
      end
      '''
      |> to_source_file("lib/media_centaur/error_reports/env_metadata.ex")
      |> run_check(PlatformBranchingDiscipline,
        grandfathered: ["lib/media_centaur/error_reports/env_metadata.ex"]
      )
      |> refute_issues()
    end

    test "files mentioning :os.type/0 only in moduledoc are not flagged" do
      ~S'''
      defmodule MediaCentaur.Watcher do
        @moduledoc """
        Branching on `:os.type/0` is not allowed here — use Platform.
        """

        def run, do: :ok
      end
      '''
      |> to_source_file("lib/media_centaur/watcher.ex")
      |> run_check(PlatformBranchingDiscipline)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test ":os.type/0 in a business module is reported" do
      ~S'''
      defmodule MediaCentaur.Watcher do
        def handle_event(events) do
          case :os.type() do
            {:unix, :darwin} -> filter_macos(events)
            _ -> events
          end
        end
      end
      '''
      |> to_source_file("lib/media_centaur/watcher.ex")
      |> run_check(PlatformBranchingDiscipline)
      |> assert_issue()
    end

    test ":os.cmd/1 in a business module is reported" do
      ~S'''
      defmodule MediaCentaur.Storage do
        def disk_info do
          :os.cmd(~c"df -k /")
        end
      end
      '''
      |> to_source_file("lib/media_centaur/storage.ex")
      |> run_check(PlatformBranchingDiscipline)
      |> assert_issue()
    end

    test "grandfathered list does not exempt other files" do
      ~S'''
      defmodule MediaCentaur.Watcher do
        def detect, do: :os.type()
      end
      '''
      |> to_source_file("lib/media_centaur/watcher.ex")
      |> run_check(PlatformBranchingDiscipline,
        grandfathered: ["lib/media_centaur/error_reports/env_metadata.ex"]
      )
      |> assert_issue()
    end
  end
end
