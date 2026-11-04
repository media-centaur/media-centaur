defmodule MediaCentaur.Credo.Checks.NativeConfirmDialogTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.NativeConfirmDialog

  describe "violations" do
    test "flags a literal data-confirm in a web template" do
      ~S'''
      defmodule MediaCentaurWeb.SomeComponent do
        use Phoenix.Component

        def wipe(assigns) do
          ~H"""
          <button phx-click="wipe" data-confirm="Are you sure?">Wipe</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeConfirmDialog)
      |> assert_issue()
    end

    test "flags an interpolated data-confirm" do
      ~S'''
      defmodule MediaCentaurWeb.SomeComponent do
        use Phoenix.Component

        def wipe(assigns) do
          ~H"""
          <button phx-click="wipe" data-confirm={"Remove #{@path}?"}>Wipe</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeConfirmDialog)
      |> assert_issue()
    end
  end

  describe "clean code" do
    test "allows a destructive action with no confirmation at all" do
      ~S'''
      defmodule MediaCentaurWeb.SomeComponent do
        use Phoenix.Component

        def wipe(assigns) do
          ~H"""
          <button phx-click="wipe">Wipe</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeConfirmDialog)
      |> refute_issues()
    end

    test "ignores non-web files that merely mention the attribute" do
      ~S'''
      defmodule MediaCentaur.SomeModule do
        @moduledoc "Never write data-confirm= on a button."
        def x, do: :ok
      end
      '''
      |> to_source_file("lib/media_centaur/some_module.ex")
      |> run_check(NativeConfirmDialog)
      |> refute_issues()
    end
  end
end
