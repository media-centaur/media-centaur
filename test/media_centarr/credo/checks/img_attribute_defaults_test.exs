defmodule MediaCentarr.Credo.Checks.ImgAttributeDefaultsTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.ImgAttributeDefaults

  describe "clean code (negative cases)" do
    test "eager + sync-decode img is allowed" do
      ~S'''
      defmodule MediaCentarrWeb.SomeComponent do
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
      |> to_source_file("lib/media_centarr_web/components/some_component.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end

    test "hero img with high fetch priority is allowed" do
      ~S'''
      defmodule MediaCentarrWeb.HomeLive do
        use MediaCentarrWeb, :live_view

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
      |> to_source_file("lib/media_centarr_web/live/home_live.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end

    test "lazy is allowed inside the cast grid (reveal-bounded surface)" do
      ~S'''
      defmodule MediaCentarrWeb.Components.Detail.MoreInfo.CastGrid do
        use Phoenix.Component

        def cast_grid(assigns) do
          ~H"""
          <img src={@headshot} loading="lazy" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/components/detail/more_info/cast_grid.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end

    test "lazy is allowed inside the track modal (search-result thumbnails)" do
      ~S'''
      defmodule MediaCentarrWeb.Components.TrackModal do
        use Phoenix.Component

        def track_modal(assigns) do
          ~H"""
          <img src={@suggestion.poster} loading="lazy" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/components/track_modal.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end

    test "files outside lib/media_centarr_web are not scanned" do
      ~S'''
      defmodule MediaCentarr.Something do
        @doc """
        <img src="..." loading="lazy" />
        """
        def x, do: :ok
      end
      '''
      |> to_source_file("lib/media_centarr/something.ex")
      |> run_check(ImgAttributeDefaults)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "lazy on an in-flow poster row is flagged" do
      ~S'''
      defmodule MediaCentarrWeb.Components.PosterRow do
        use Phoenix.Component

        def poster_row(assigns) do
          ~H"""
          <img src={item.poster_url} loading="lazy" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/components/poster_row.ex")
      |> run_check(ImgAttributeDefaults)
      |> assert_issue()
    end

    test "lazy on a library card is flagged" do
      ~S'''
      defmodule MediaCentarrWeb.Components.LibraryCards do
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
      |> to_source_file("lib/media_centarr_web/components/library_cards.ex")
      |> run_check(ImgAttributeDefaults)
      |> assert_issue()
    end

    test "lazy in a LiveView render block is flagged" do
      ~S'''
      defmodule MediaCentarrWeb.SomeLive do
        use MediaCentarrWeb, :live_view

        def render(assigns) do
          ~H"""
          <img src="/x.jpg" loading="lazy" />
          <img src="/y.jpg" loading="lazy" />
          """
        end
      end
      '''
      |> to_source_file("lib/media_centarr_web/live/some_live.ex")
      |> run_check(ImgAttributeDefaults)
      |> assert_issues(fn issues -> length(issues) == 2 end)
    end
  end
end
