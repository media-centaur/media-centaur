defmodule MediaCentaur.Credo.Checks.ReadableTextContrastTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.ReadableTextContrast

  defp web_source(heex) do
    ~S'''
    defmodule MediaCentaurWeb.SomeLive do
      use Phoenix.LiveView

      def render(assigns) do
        ~H"""
    '''
    |> Kernel.<>(heex)
    |> Kernel.<>(~S'''
        """
      end
    end
    ''')
    |> to_source_file("lib/media_centaur_web/live/some_live.ex")
  end

  describe "clean code (negative cases)" do
    test "text at or above the floor passes" do
      ~S'''
      <p class="text-sm text-base-content/55">Last scanned</p>
      <p class="text-sm text-base-content/60">Last scanned</p>
      <h3 class="text-xs uppercase tracking-wider text-base-content/80">Library</h3>
      '''
      |> web_source()
      |> run_check(ReadableTextContrast)
      |> refute_issues()
    end

    test "icons, spinners, separators, placeholders and disabled states may go dimmer" do
      ~S'''
      <.icon name="hero-film" class="size-10 text-base-content/30" />
      <span class="loading loading-spinner loading-xs text-base-content/30" />
      <span class="text-base-content/30 select-none">·</span>
      <span class="text-base-content/40">&middot;</span>
      <input class="placeholder:text-base-content/40" />
      <button class="disabled:text-base-content/40">Save</button>
      '''
      |> web_source()
      |> run_check(ReadableTextContrast)
      |> refute_issues()
    end

    test "a variant-prefixed opacity is not the resting state" do
      ~S'''
      <a class="text-base-content/60 hover:text-base-content/40">More</a>
      '''
      |> web_source()
      |> run_check(ReadableTextContrast)
      |> refute_issues()
    end

    test "files outside the web layer are ignored" do
      ~S'''
      defmodule MediaCentaur.Something do
        def class, do: "text-base-content/40"
      end
      '''
      |> to_source_file("lib/media_centaur/something.ex")
      |> run_check(ReadableTextContrast)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "small text below the floor is flagged with the offending class" do
      ~S'''
      <p class="text-sm text-base-content/40">Last scanned</p>
      '''
      |> web_source()
      |> run_check(ReadableTextContrast)
      |> assert_issue(fn issue ->
        assert issue.trigger == "text-base-content/40"
        assert issue.line_no == 6
      end)
    end

    test "/50 section headers are below the floor" do
      ~S'''
      <h3 class="text-xs uppercase tracking-wider text-base-content/50">Library</h3>
      '''
      |> web_source()
      |> run_check(ReadableTextContrast)
      |> assert_issue()
    end

    test "class strings returned from helpers are held to the same floor" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        def tone_class(:muted), do: "text-base-content/35"
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(ReadableTextContrast)
      |> assert_issue()
    end
  end
end
