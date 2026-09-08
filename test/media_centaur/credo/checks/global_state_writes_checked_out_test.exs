defmodule MediaCentaur.Credo.Checks.GlobalStateWritesCheckedOutTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.GlobalStateWritesCheckedOut

  describe "clean code" do
    test "a sync test may write global state" do
      """
      defmodule SomeTest do
        use MediaCentaur.Case, async: false

        test "x" do
          :persistent_term.put({MediaCentaur.Thing, :state}, :value)
          Application.put_env(:media_centaur, :environment, :prod)
          Config.update(:exclude_dirs, [])
        end
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(GlobalStateWritesCheckedOut)
      |> refute_issues()
    end

    test "an async test that only reads is fine" do
      """
      defmodule SomeTest do
        use MediaCentaur.Case, async: true

        test "x" do
          assert :persistent_term.get({MediaCentaur.Thing, :state}, nil) == nil
          assert Application.get_env(:media_centaur, :environment) == :test
        end
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(GlobalStateWritesCheckedOut)
      |> refute_issues()
    end
  end

  describe "violations — an async test owns nothing global" do
    for {label, call, trigger} <- [
          {":persistent_term.put", ":persistent_term.put({MediaCentaur.Thing, :state}, :value)",
           ":persistent_term.put"},
          {":persistent_term.erase", ":persistent_term.erase({MediaCentaur.Thing, :state})",
           ":persistent_term.erase"},
          {"Application.put_env", "Application.put_env(:media_centaur, :environment, :prod)",
           "Application.put_env"},
          {"Application.delete_env", "Application.delete_env(:media_centaur, :environment)",
           "Application.delete_env"},
          {"Config.update", "Config.update(:exclude_dirs, [])", "Config.update"},
          {"a fully qualified Config.put_media_dirs", "MediaCentaur.Settings.Config.put_media_dirs([])",
           "MediaCentaur.Settings.Config.put_media_dirs"},
          {"Req.Test.set_req_test_to_shared", "Req.Test.set_req_test_to_shared()",
           "Req.Test.set_req_test_to_shared"},
          {"System.put_env", ~s|System.put_env("MEDIA_CENTAUR_CONFIG_OVERRIDE", "x")|, "System.put_env"}
        ] do
      test "#{label} in an async test is flagged" do
        """
        defmodule SomeTest do
          use MediaCentaur.Case, async: true

          test "x" do
            #{unquote(call)}
          end
        end
        """
        |> to_source_file("test/media_centaur/some_test.exs")
        |> run_check(GlobalStateWritesCheckedOut)
        |> assert_issue(fn issue ->
          assert issue.trigger == unquote(trigger)
          assert issue.message =~ "checked-out"
        end)
      end
    end

    test "a write in setup_all is outside every checkout, even in a sync module" do
      """
      defmodule SomeTest do
        use MediaCentaur.Case, async: false

        setup_all do
          Application.put_env(:media_centaur, :flush_interval_ms, 50)
          :ok
        end

        setup do
          Application.put_env(:media_centaur, :environment, :prod)
        end
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(GlobalStateWritesCheckedOut)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Application.put_env"
        assert issue.line_no == 5
      end)
    end

    test "adding a child to the app supervisor in setup_all is a write" do
      """
      defmodule SomeTest do
        use MediaCentaur.DataCase, async: false

        setup_all do
          Supervisor.start_child(MediaCentaur.Supervisor, MediaCentaur.Review.Intake)
          :ok
        end
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(GlobalStateWritesCheckedOut)
      |> assert_issue(fn issue -> assert issue.trigger == "Supervisor.start_child" end)
    end

    test "a context function that writes a cache counts as a write" do
      """
      defmodule SomeTest do
        use MediaCentaur.Case, async: true

        setup do
          UpdateChecker.cache_result({:ok, release})
        end
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(GlobalStateWritesCheckedOut)
      |> assert_issue(fn issue -> assert issue.trigger == "UpdateChecker.cache_result" end)
    end

    test "an async DataCase counts as async" do
      """
      defmodule SomeTest do
        use MediaCentaur.DataCase, async: true

        setup do
          :persistent_term.put({MediaCentaur.Thing, :state}, :value)
        end
      end
      """
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(GlobalStateWritesCheckedOut)
      |> assert_issue(fn issue -> assert issue.trigger == ":persistent_term.put" end)
    end
  end
end
