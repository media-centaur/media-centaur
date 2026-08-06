defmodule MediaCentaurWeb.ArtworkWarmup do
  @moduledoc """
  First-screen artwork URLs for the root layout's `<link rel="prefetch">`
  hints (instant-navigation campaign Phase 4).

  UIDR-012 mandates `loading="eager" decoding="sync"` — a page paints only
  once its artwork is decoded — which makes the first visit to a
  poster-heavy page pay fetch + decode on the click path (~250–550ms
  measured on /library). These hints let the browser pull the artwork
  into its HTTP cache at launch, at its lowest priority, so every later
  first visit behaves like a warm one (~50–70ms).

  Two rules keep this honest:

    * **URLs must be byte-identical to what the pages request** — the
      poster list goes through the same `sized_image_url/2` the library
      grid uses, and backdrops are the raw `backdrop_url` the
      hero-candidate pool hands to the library/incoming pages. Any
      mismatch is a cache miss and the hint is dead weight.
    * **Reads are projection-only** (`Library.Views` ETS) — the root
      layout renders on the initial HTTP request, and this must add
      nothing to that path.
  """

  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Library
  alias MediaCentaurWeb.HomeLive.Logic

  @poster_limit 30
  @poster_width 640

  @doc """
  Deduplicated first-screen artwork URLs: up to #{@poster_limit} library
  grid poster derivatives plus the hero-candidate backdrops the
  home/library/incoming pages draw from.
  """
  @spec urls() :: [String.t()]
  def urls do
    (poster_urls() ++ backdrop_urls())
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp poster_urls do
    Library.Views.browse()
    |> Enum.map(& &1.poster_url)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@poster_limit)
    |> Enum.map(&sized_image_url(&1, @poster_width))
  end

  # Only the candidates the backdrop-bearing pages are showing right now.
  # The rotation means the eligible pool is far larger than what any page
  # will request before the next block, so warming the whole pool would
  # prefetch dozens of images nobody loads. Asking `select_page_hero/2` for
  # each slot keeps this in lockstep with what the pages actually render.
  defp backdrop_urls do
    case Library.Views.hero_candidates() do
      [] ->
        []

      candidates ->
        0..(Logic.hero_pages() - 1)
        |> Enum.map(&Logic.select_page_hero(candidates, &1).backdrop_url)
        |> Enum.uniq()
    end
  end
end
