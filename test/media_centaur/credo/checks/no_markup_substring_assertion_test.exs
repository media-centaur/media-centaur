defmodule MediaCentaur.Credo.Checks.NoMarkupSubstringAssertionTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.NoMarkupSubstringAssertion

  describe "violations — substring-matching HTML attributes" do
    test "a phx- binding assertion is flagged" do
      ~S'''
      defmodule SomeLiveTest do
        test "x" do
          assert html =~ "phx-click=\"retry_search\""
        end
      end
      '''
      |> to_source_file("test/media_centaur_web/live/some_live_test.exs")
      |> run_check(NoMarkupSubstringAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "has_element?"
      end)
    end

    test "a data- attribute assertion is flagged" do
      ~S'''
      defmodule SomeLiveTest do
        test "x" do
          refute html =~ "data-nav-zone=\"zone-tabs\""
        end
      end
      '''
      |> to_source_file("test/media_centaur_web/live/some_live_test.exs")
      |> run_check(NoMarkupSubstringAssertion)
      |> assert_issue()
    end

    test "a bare data- attribute name is flagged" do
      ~S'''
      defmodule SomeLiveTest do
        test "x" do
          refute html =~ "data-zone-tab"
        end
      end
      '''
      |> to_source_file("test/media_centaur_web/live/some_live_test.exs")
      |> run_check(NoMarkupSubstringAssertion)
      |> assert_issue()
    end

    test "a class or id attribute assertion is flagged" do
      ~S'''
      defmodule SomeLiveTest do
        test "x" do
          assert html =~ "id=\"browse\""
          assert html =~ "class=\"card\""
        end
      end
      '''
      |> to_source_file("test/media_centaur_web/live/some_live_test.exs")
      |> run_check(NoMarkupSubstringAssertion)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end
  end

  describe "allowed — user-visible copy and non-markup strings" do
    test "asserting on rendered copy is allowed" do
      ~S'''
      defmodule SomeLiveTest do
        test "x" do
          assert html =~ "What do you want to watch?"
          assert html =~ "Connect a download client"
        end
      end
      '''
      |> to_source_file("test/media_centaur_web/live/some_live_test.exs")
      |> run_check(NoMarkupSubstringAssertion)
      |> refute_issues()
    end

    test "redaction placeholders that merely look like tags are allowed" do
      ~S'''
      defmodule RedactorTest do
        test "x" do
          assert Redactor.normalize(input) =~ "<uuid>"
          assert event.message =~ "<path>"
        end
      end
      '''
      |> to_source_file("test/media_centaur/error_reports/redactor_test.exs")
      |> run_check(NoMarkupSubstringAssertion)
      |> refute_issues()
    end

    test "a word merely containing `data-` is not an attribute" do
      ~S'''
      defmodule SomeLiveTest do
        test "x" do
          assert html =~ "metadata-activity"
        end
      end
      '''
      |> to_source_file("test/media_centaur_web/live/some_live_test.exs")
      |> run_check(NoMarkupSubstringAssertion)
      |> refute_issues()
    end

    test "a query-string fragment is not markup" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          assert result.summary =~ "rid=7"
        end
      end
      '''
      |> to_source_file("test/media_centaur/downloads/some_test.exs")
      |> run_check(NoMarkupSubstringAssertion)
      |> refute_issues()
    end

    test "application code is out of scope" do
      ~S'''
      defmodule MediaCentaurWeb.Thing do
        def check(html), do: html =~ "phx-click=\"go\""
      end
      '''
      |> to_source_file("lib/media_centaur_web/thing.ex")
      |> run_check(NoMarkupSubstringAssertion)
      |> refute_issues()
    end
  end
end
