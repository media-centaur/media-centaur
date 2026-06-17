defmodule MediaCentaur.Credo.Checks.NoPhxValueValueTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.NoPhxValueValue

  describe "violations" do
    test "flags phx-value-value on a button in a web template" do
      ~S'''
      defmodule MediaCentaurWeb.SomeComponent do
        use Phoenix.Component

        def pick(assigns) do
          ~H"""
          <button phx-click="pick" phx-value-value={@v}>x</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/some_component.ex")
      |> run_check(NoPhxValueValue)
      |> assert_issue()
    end
  end

  describe "clean code" do
    test "allows a descriptively named key" do
      ~S'''
      defmodule MediaCentaurWeb.SomeComponent do
        use Phoenix.Component

        def pick(assigns) do
          ~H"""
          <button phx-click="pick" phx-value-choice={@v}>x</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/some_component.ex")
      |> run_check(NoPhxValueValue)
      |> refute_issues()
    end

    test "allows phx-value-name (does not collide)" do
      ~S'''
      defmodule MediaCentaurWeb.SomeComponent do
        use Phoenix.Component

        def pick(assigns) do
          ~H"""
          <button phx-click="pick" phx-value-name={@name}>x</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/some_component.ex")
      |> run_check(NoPhxValueValue)
      |> refute_issues()
    end

    test "ignores non-web files (e.g. prose mentioning the attribute)" do
      ~S'''
      defmodule MediaCentaur.SomeModule do
        @moduledoc "Never write phx-value-value=... on a button."
        def x, do: :ok
      end
      '''
      |> to_source_file("lib/media_centaur/some_module.ex")
      |> run_check(NoPhxValueValue)
      |> refute_issues()
    end
  end
end
