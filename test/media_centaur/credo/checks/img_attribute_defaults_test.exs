defmodule MediaCentaur.Credo.Checks.ImgAttributeDefaultsTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.ImgAttributeDefaults

  describe "clean code (negative cases)" do
    test "eager + sync-decode img is allowed" do
      ~S'''
      defmodule MediaCentaurWeb.SomeComponent do
        use Phoenix.Component

        def card(assigns) do
          ~H"""
          <img
            src={@poster_url}
            loading="eager"
            decoding="sync"
          />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/some_component.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end

    test "hero img with high fetch priority is allowed" do
      ~S'''
      defmodule MediaCentaurWeb.HomeLive do
        use MediaCentaurWeb, :live_view

        def render(assigns) do
          ~H"""
          <img
            src={@hero.backdrop_url}
            loading="eager"
            decoding="sync"
            fetchpriority="high"
          />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/home_live.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end

    test "lazy is allowed inside the cast grid (reveal-bounded surface)" do
      ~S'''
      defmodule MediaCentaurWeb.Components.Detail.CastGrid do
        use Phoenix.Component

        def cast_grid(assigns) do
          ~H"""
          <img src={@headshot} loading="lazy" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/detail/cast_grid.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end

    test "a file dropped from the exempt list is scanned again" do
      # TrackModal was an exempt surface until its retirement (the
      # suggestion strip moved into the omnibox, eager like the rest of
      # the page flow) — a leftover lazy in a non-exempt component must
      # flag.
      ~S'''
      defmodule MediaCentaurWeb.Components.SomeSurface do
        use Phoenix.Component

        def some_surface(assigns) do
          ~H"""
          <img src={@poster} loading="lazy" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/some_surface.ex")
      |> run_check(ImgAttributeDefaults)
      |> assert_issue()
    end

    test "files outside lib/media_centaur_web are not scanned" do
      ~S'''
      defmodule MediaCentaur.Something do
        @doc """
        <img src="..." loading="lazy" />
        """
        def x, do: :ok
      end
      '''
      |> to_source_file("lib/media_centaur/something.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "lazy on an in-flow poster row is flagged" do
      ~S'''
      defmodule MediaCentaurWeb.Components.PosterRow do
        use Phoenix.Component

        def poster_row(assigns) do
          ~H"""
          <img src={item.poster_url} loading="lazy" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/poster_row.ex")
      |> run_check(ImgAttributeDefaults)
      |> assert_issue()
    end

    test "lazy on a library card is flagged" do
      ~S'''
      defmodule MediaCentaurWeb.Components.LibraryCards do
        use Phoenix.Component

        def poster_card(assigns) do
          ~H"""
          <img
            src={@entry.poster_url}
            class="w-full"
            loading="lazy"
          />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/components/library_cards.ex")
      |> run_check(ImgAttributeDefaults)
      |> assert_issue()
    end

    test "lazy in a LiveView render block is flagged" do
      ~S'''
      defmodule MediaCentaurWeb.SomeLive do
        use MediaCentaurWeb, :live_view

        def render(assigns) do
          ~H"""
          <img src="/x.jpg" loading="lazy" />
          <img src="/y.jpg" loading="lazy" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centaur_web/live/some_live.ex")
      |> run_check(ImgAttributeDefaults)
      |> assert_issues(fn issues -> length(issues) == 2 end)
    end
  end
end
