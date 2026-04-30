defmodule MediaCentarr.Credo.Checks.RawButtonClassTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.RawButtonClass

  describe "clean code (negative cases)" do
    test "<.button> component usage is allowed" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <.button variant="primary" size="lg" phx-click="save">Save</.button>
          <.button variant="dismiss" phx-click="cancel">Cancel</.button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawButtonClass)
      |> refute_issues()
    end

    test "the button component file itself is allowed to write `btn` literally" do
      ~S'''
      defmodule MediaCentarrWeb.CoreComponents do
        use Phoenix.Component

        def button(assigns) do
          assigns = assign(assigns, :class, ["btn", "btn-primary"])

          ~H"""
          <button class={@class}>{render_slot(@inner_block)}</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/components/core_components.ex")
      |> run_check(RawButtonClass)
      |> refute_issues()
    end

    test "custom CSS classes ending in -btn are allowed (no standalone btn token)" do
      ~S'''
      defmodule MediaCentarrWeb.SettingsLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <button class="controls-icon-btn">x</button>
          <span class="hint-btn" data-btn="a">A</span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/settings_live.ex")
      |> run_check(RawButtonClass)
      |> refute_issues()
    end

    test "class without btn token is allowed" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <button class="text-error opacity-60">x</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawButtonClass)
      |> refute_issues()
    end

    test "files outside lib/media_centarr_web/ are not scanned" do
      ~S'''
      defmodule MediaCentarr.NotATemplate do
        @moduledoc "btn btn-primary"
        def html_string, do: ~s(<button class="btn btn-primary">x</button>)
      end
      '''
      |> to_source_file("lib/media_centarr/not_a_template.ex")
      |> run_check(RawButtonClass)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "raw btn class in a LiveView render is reported" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <button class="btn btn-primary" phx-click="save">Save</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawButtonClass)
      |> assert_issue()
    end

    test "raw btn class in a function component is reported" do
      ~S'''
      defmodule MediaCentarrWeb.MyComponent do
        use Phoenix.Component

        def some_button(assigns) do
          ~H"""
          <a class="btn btn-soft btn-primary btn-sm" href="/">Home</a>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/components/my_component.ex")
      |> run_check(RawButtonClass)
      |> assert_issue()
    end

    test "raw btn-only class is reported" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <button class="btn">Save</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawButtonClass)
      |> assert_issue()
    end

    test "raw btn class with leading utility classes is reported" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <button class="absolute top-3 right-3 btn btn-ghost btn-sm">x</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawButtonClass)
      |> assert_issue()
    end

    test "two violations on separate lines produce two issues" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <button class="btn btn-primary">A</button>
          <button class="btn btn-ghost">B</button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(RawButtonClass)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end
  end
end
