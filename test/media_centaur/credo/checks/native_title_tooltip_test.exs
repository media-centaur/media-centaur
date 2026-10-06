defmodule MediaCentaur.Credo.Checks.NativeTitleTooltipTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.NativeTitleTooltip

  describe "clean code (negative cases)" do
    test "data-tip on an element or a button is allowed" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <span class="truncate-left" data-tip={@path}><bdo dir="ltr">{@path}</bdo></span>
          <.button variant="dismiss" data-tip="Close" aria-label="Close">x</.button>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeTitleTooltip)
      |> refute_issues()
    end

    test "a component attribute named title is data, not a tooltip" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <.page_header title="Library" />
          <TitleLayer.lockup
            title={@name}
            logo_url={@logo_url}
          />
          <.list>
            <:item title="Views">{@views}</:item>
          </.list>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeTitleTooltip)
      |> refute_issues()
    end

    test "title in text, a URL or a namespaced attribute is not a title attribute" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <button phx-click="pick" phx-value-title={@title} data-title="x">
            Open ?title=movie-1 — the title={@title} prose
          </button>
          <.live_title default="MediaCentaur">{@page_title}</.live_title>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeTitleTooltip)
      |> refute_issues()
    end

    test "title= inside a brace expression is not an attribute" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <a href={"/search?q=#{@q}&kind=" <> "x title=y"} class={if @a > 1, do: "b"}>go</a>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeTitleTooltip)
      |> refute_issues()
    end

    test "prose in a moduledoc or a plain string is not markup" do
      ~S'''
      defmodule MediaCentaurWeb.Components.Prompt do
        @moduledoc """
        Renders "You finished <title>" over a row whose <span title=…> is gone.
        """
        use Phoenix.Component

        def label(title), do: "<title>" <> title
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/prompt.ex")
      |> run_check(NativeTitleTooltip)
      |> refute_issues()
    end

    test "files outside lib/media_centaur_web/ are not scanned" do
      ~S'''
      defmodule MediaCentaur.NotATemplate do
        def html_string, do: ~s(<span title="x">x</span>)
      end
      '''
      |> to_source_file("lib/media_centaur/not_a_template.ex")
      |> run_check(NativeTitleTooltip)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "title attribute on an HTML element is reported, on the attribute's line" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <span
            class="truncate-left"
            title={@path}
          >
            {@path}
          </span>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeTitleTooltip)
      |> assert_issue(fn issue -> assert issue.line_no == 8 end)
    end

    test "title on <.button> and <.link> is reported — they forward it to a native element" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <.button variant="dismiss" title="Close" phx-click={if @a, do: "x", else: "y"}>x</.button>
          <.link navigate={~p"/"} title={@name}>Home</.link>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/some_component.ex")
      |> run_check(NativeTitleTooltip)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end

    test "an SVG <title> element is reported" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <svg><rect x="0" y="0"><title>{@label}</title></rect></svg>
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeTitleTooltip)
      |> assert_issue()
    end

    test "a title attribute on an img is reported even with alt present" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use Phoenix.LiveView

        def render(assigns) do
          ~H"""
          <img src={@url} alt={@title} title={@title} loading="eager" decoding="sync" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(NativeTitleTooltip)
      |> assert_issue()
    end
  end
end
