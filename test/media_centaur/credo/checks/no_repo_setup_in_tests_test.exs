defmodule MediaCentaur.Credo.Checks.NoRepoSetupInTestsTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.NoRepoSetupInTests

  describe "violations — Repo writes are setup" do
    test "Repo.insert in a test is flagged" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          {:ok, record} = Repo.insert(%Thing{name: "a"})
        end
      end
      '''
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(NoRepoSetupInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Repo.insert"
        assert issue.message =~ "TestFactory"
      end)
    end

    test "a fully qualified MediaCentaur.Repo.update! is flagged" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          pursuit |> Ecto.Changeset.change(state: "done") |> MediaCentaur.Repo.update!()
        end
      end
      '''
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(NoRepoSetupInTests)
      |> assert_issue()
    end

    test "Repo.delete_all is flagged" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          Repo.delete_all(Thing)
        end
      end
      '''
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(NoRepoSetupInTests)
      |> assert_issue()
    end
  end

  describe "allowed — Repo reads are assertions" do
    test "Repo.get! for an assertion is allowed" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          assert Repo.get!(Thing, id).name == "a"
        end
      end
      '''
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(NoRepoSetupInTests)
      |> refute_issues()
    end

    test "Repo.all / one / aggregate / exists? / preload are allowed" do
      ~S'''
      defmodule SomeTest do
        test "x" do
          assert Repo.all(Thing) != []
          assert Repo.one(query)
          assert Repo.aggregate(Thing, :count) == 1
          assert Repo.exists?(Thing)
          assert Repo.preload(record, :parent).parent
        end
      end
      '''
      |> to_source_file("test/media_centaur/some_test.exs")
      |> run_check(NoRepoSetupInTests)
      |> refute_issues()
    end

    test "the factory itself may write — that is where setup belongs" do
      ~S'''
      defmodule MediaCentaur.TestFactory do
        def force_attrs(record, attrs) do
          record |> Ecto.Changeset.change(Map.new(attrs)) |> MediaCentaur.Repo.update!()
        end
      end
      '''
      |> to_source_file("test/support/factory.ex")
      |> run_check(NoRepoSetupInTests)
      |> refute_issues()
    end

    test "application code is out of scope" do
      ~S'''
      defmodule MediaCentaur.Review do
        def create(attrs), do: Repo.insert(changeset(attrs))
      end
      '''
      |> to_source_file("lib/media_centaur/review.ex")
      |> run_check(NoRepoSetupInTests)
      |> refute_issues()
    end
  end
end
